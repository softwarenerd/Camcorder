//
//  Camcorder.m
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "libkern/OSAtomic.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <ImageIO/CGImageProperties.h>
#import "AtomicFlag.h"
#import "Camcorder.h"
#import "MovieWriter.h"

// Local defines.
#define OUTPUT_QUEUE "camcorder.output"

// Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) interface.
@interface Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@end

// Camcorder (Internal) interface.
@interface Camcorder (Internal)

// Returns an AVCaptureConnection* matching the specified media type from the specified array of connections.
+ (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections;

// Returns the camera with the specificed AVCaptureDevicePosition. If a camera with the specificed
// AVCaptureDevicePosition cannot be found, reutrns nil.
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position;

// Returns the first audio device, if it was found; otherwise, nil.
- (AVCaptureDevice *)audioDevice;

// AVCaptureDeviceWasConnectedNotification observer callback.
- (void)captureDeviceWasConnectedNotification:(NSNotification *)notification;

// AVCaptureDeviceWasDisconnectedNotification observer callback.
- (void)captureDeviceWasDisconnectedNotification:(NSNotification *)notification;

// Auto off timer callback.
- (void)autoOffTimerCallback:(NSTimer *)timer;

// Recording timer callback.
- (void)recordingTimerCallback:(NSTimer *)timer;

@end

// Camcorder implementation.
@implementation Camcorder
{
@private
    // The output directory URL.
    NSURL * outputDirectoryURL_;
    
    // The width.
    NSUInteger width_;
    
    // The height.
    NSUInteger height_;
    
    // A value which indicates whether to capture audio.
    BOOL captureAudio_;
    
    // A value which indicates whether the camcorder has been started.
    AtomicFlag * atomicFlagStarted_;
    
    // A value which indicates whether the camcorder is on.
    AtomicFlag * atomicFlagIsOn_;
    
    // A value which indicates whether the camcorder is recording.
    AtomicFlag * atomicFlagIsRecording_;
    
    // The capture session. All video and audio inputs and outputs are
    // connected to the capture session.
    AVCaptureSession * captureSession_;
    
    // The capture video preview layer that displays a preview of the
    // capture session. This is a singleton instance which is created
    // the first time it is asked for.
    AVCaptureVideoPreviewLayer * captureVideoPreviewLayer_;

    // The capture device input for video.
    AVCaptureDeviceInput * captureDeviceInputVideo_;
    
    // The capture device input for audio.
    AVCaptureDeviceInput * captureDeviceInputAudio_;
    
    // The capture video data output. Delivers video buffers to our 
    // AVCaptureVideoDataOutputSampleBufferDelegate implementation.
    AVCaptureVideoDataOutput * captureVideoDataOutput_;
    
    // The capture audio data output. Delivers audio buffers to our 
    // AVCaptureVideoDataOutputSampleBufferDelegate implementation.
    AVCaptureAudioDataOutput * captureAudioDataOutput_;

    // The capture output queue.
    dispatch_queue_t captureOutputQueue_;
       
    // Auto off timer.
    NSTimer * autoOffTimer_;
    
    // The movie writer.
    MovieWriter * movieWriter_;

    // The timer used to fire videoCamera:recordingElapsedTimeInterval: callbacks to the VideoCameraDelegate.
    NSTimer * recordingTimer_;
}

// Gets or sets the delegate.
@synthesize delegate = delegate_;

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                    captureAudio:(BOOL)captureAudio
{
    // Initialize superclass.
    self = [super init];
        
    // Handle errors.
    if (!self)
    {
        return nil;
    }
    
    // Initialize.
    outputDirectoryURL_ = outputDirectoryURL;
    width_ = width;
    height_ = height;
    captureAudio_ = captureAudio;
    atomicFlagStarted_ = [[AtomicFlag alloc] init];
    atomicFlagIsOn_ = [[AtomicFlag alloc] init];
    atomicFlagIsRecording_ = [[AtomicFlag alloc] init];
        
    // Create the output queue.
    captureOutputQueue_ = dispatch_queue_create(OUTPUT_QUEUE, DISPATCH_QUEUE_SERIAL);

    // Get the default notification center.
    NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
    
    // Add AVCaptureDeviceWasConnectedNotification observer.
    [notificationCenter addObserver:self
                           selector:@selector(captureDeviceWasConnectedNotification:)
                               name:AVCaptureDeviceWasConnectedNotification
                             object:nil];
    
    // Add AVCaptureDeviceWasDisconnectedNotification observer.
    [notificationCenter addObserver:self
                           selector:@selector(captureDeviceWasDisconnectedNotification:)
                               name:AVCaptureDeviceWasDisconnectedNotification
                             object:nil];
    
    // Done.
    return self;
}

// Dealloc.
- (void)dealloc
{
    // Release the capture output queue.
    dispatch_release(captureOutputQueue_);    
    
    // Get the default notification center.
    NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
    
    // Remove AVCaptureDeviceWasConnectedNotification observer.
    [notificationCenter removeObserver:self
                                  name:AVCaptureDeviceWasConnectedNotification
                                object:nil];
    
    // Remove AVCaptureDeviceWasDisconnectedNotification observer.
    [notificationCenter removeObserver:self
                                  name:AVCaptureDeviceWasDisconnectedNotification
                                object:nil];
}

- (BOOL)start
{
    // If the delegate has not been set, return NO.
    if (!delegate_)
    {
        return NO;
    }
    
    // Create capture session. Set it to HD video.
    captureSession_ = [[AVCaptureSession alloc] init];
    //[captureSession_ setSessionPreset:AVCaptureSessionPresetHigh];        

    // Create the capture video data output.
    captureVideoDataOutput_ = [[AVCaptureVideoDataOutput alloc] init];
	[captureVideoDataOutput_ setAlwaysDiscardsLateVideoFrames:NO];
	[captureVideoDataOutput_ setSampleBufferDelegate:self queue:captureOutputQueue_];

    // If we can't add the video output, report the failure 
    if (![captureSession_ canAddOutput:captureVideoDataOutput_])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorStartVideoOutput userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return false;
    }
    
    // Add the video output.
    [captureSession_ addOutput:captureVideoDataOutput_];
    
    // Initialize audio capture.
    if (captureAudio_)
    {
        // Add new audio capture device input.
        NSError * error;
        AVCaptureDeviceInput * captureDeviceInputAudio = [[AVCaptureDeviceInput alloc] initWithDevice:[self audioDevice] error:&error];
        if (error)
        {
            [[self delegate] camcorder:self didFailWithError:error];
            return false;
        }
        
        // If we can't add the audio input, report the failure.
        if (![captureSession_ canAddInput:captureDeviceInputAudio])
        {
            captureDeviceInputAudio_ = captureDeviceInputAudio;
            return NO;
        }
        
        // Add the audio input.
        [captureSession_ addInput:captureDeviceInputAudio];

        // Create the capture audio data output.
        captureAudioDataOutput_ = [[AVCaptureAudioDataOutput alloc] init];
        [captureAudioDataOutput_ setSampleBufferDelegate:self queue:captureOutputQueue_];
        
        // If we can't add the audio output, report the failure 
        if (![captureSession_ canAddOutput:captureAudioDataOutput_])
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorStartAudioOutput userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return false;
        }

        // Add the audio output.
        [captureSession_ addOutput:captureAudioDataOutput_];
    }    
    
    // Success.
    return YES;
}

// Sets the camera position.
- (void)setCameraPosition:(CameraPosition)cameraPosition
{
    // Select the capture device position.
    AVCaptureDevicePosition captureDevicePosition;
    if (cameraPosition == CameraPositionBack)
    {
        captureDevicePosition = AVCaptureDevicePositionBack;
    }
    else if (cameraPosition == CameraPositionFront)
    {
        captureDevicePosition = AVCaptureDevicePositionFront;
    }
    else
    {
        // Can't get here unless a new entry is added to the enum and this code isn't updated.
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Unsupported camera position."
                                     userInfo:nil];
    }
    
    // If we have a video capture device input and its position is what it is supposed to be, return. 
    if (captureDeviceInputVideo_ && [[captureDeviceInputVideo_ device] position] == captureDevicePosition)
    {
        return;
    }

    // Reconfigure the capture session.
    [captureSession_ beginConfiguration];
        
    // Remove existing video capture device input.
    if (captureDeviceInputVideo_)
    {
        [captureSession_ removeInput:captureDeviceInputVideo_];
        captureDeviceInputVideo_ = nil;
    }
        
    // Add new video capture device input.
    NSError * error;
    AVCaptureDeviceInput * captureDeviceInputVideo = [[AVCaptureDeviceInput alloc] initWithDevice:[self cameraWithPosition:captureDevicePosition] error:&error];
    if (error)
    {
        [[self delegate] camcorder:self didFailWithError:error];
    }
    else
    {
        if ([captureSession_ canAddInput:captureDeviceInputVideo])
        {
            [captureSession_ addInput:captureDeviceInputVideo];
            captureDeviceInputVideo_ = captureDeviceInputVideo;
        }
    }

    // Complete the operation.
    [captureSession_ commitConfiguration];
}

// Gets a value indicating whether the camcorder is on.
- (BOOL)isOn
{
    return [atomicFlagIsOn_ isSet];
}

// Gets a value indicating whether the camcorder is recording.
- (BOOL)isRecording
{
    return [atomicFlagIsRecording_ isSet];
}

// Returns a AVCaptureVideoPreviewLayer for the camcorder.
- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer
{
    // Allocate the capture video preview layer, if it hasn't already been allocated.
    if (!captureVideoPreviewLayer_)
    {
        captureVideoPreviewLayer_ = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession_];
    }
    
    // Return the capture video preview layer.
    return captureVideoPreviewLayer_;
}

// Turns the camcorder on.
- (void)turnOn
{
    // If the camera is on, return.
    if (![atomicFlagIsOn_ trySet])
    {
        return;
    }
    
    // The block that turns the camera on.
    void (^turnCamcorderOnBlock)() = ^
    {
        // Start the capture session.
        [captureSession_ startRunning];
        
        // Inform the delegate.
        [[self delegate] camcorderDidTurnOn:self];        
    };
        
    // Start the session asychronously.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), turnCamcorderOnBlock);
}

// Turns the camcorder off.
- (void)turnOff
{
    // If the camera is off, return.
    if (![atomicFlagIsOn_ tryClear])
    {
        return;
    }

    // Stops the auto off timer.
    [self stopAutoOffTimer];
        
    // The block that turns the camera off.
    void (^turnCamcorderOffBlock)() = ^
    {
        // Stop the capture session.
        [captureSession_ stopRunning];
        
        // Inform the delegate.
        [[self delegate] camcorderDidTurnOff:self];
    };

    // Stop the session asychronously.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), turnCamcorderOffBlock);
}

// Starts the auto off timer.
- (void)startAutoOffTimer
{
    // Start the auto off timer.
    if (!autoOffTimer_)
    {
        NSLog(@"Enable auto off timer.");
        autoOffTimer_ = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                         target:self
                                                       selector:@selector(autoOffTimerCallback:)
                                                       userInfo:nil
                                                        repeats:NO];
    }
}

// Stops the auto off timer.
- (void)stopAutoOffTimer
{
    // Kill the auto off timer.
    if (autoOffTimer_)
    {
        NSLog(@"Disable auto off timer.");
        [autoOffTimer_ invalidate];
        autoOffTimer_ = nil;
    }    
}

// Starts recording.
- (void)startRecording
{
    [self startRecordingWithTimeInterval:nil];
}

// Starts recording with an optional time interval.
- (void)startRecordingWithTimeInterval:(NSTimeInterval *)timeInterval
{
    // Set the recording flag.
    if ([atomicFlagIsRecording_ trySet])
    {
        // Stop the auto off timer.
        [self stopAutoOffTimer];
             
        // Allocate and initialize the movie output.
        movieWriter_ = [[MovieWriter alloc] initWithOutputDirectoryURL:outputDirectoryURL_ width:width_ height:height_ audio:captureAudio_];
        [movieWriter_ begin];
        
#if false
        // Start the recording timer that emits videoCamera:recordingElapsedTimeInterval: calls to
        // the delegate.
        recordingTimer_ = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                           target:self
                                                         selector:@selector(recordingTimerCallback:)
                                                         userInfo:nil
                                                          repeats:YES];
#endif
    }    
}

// Stops recording.
- (void)stopRecording
{
    // Try to stop recording.
    if (![atomicFlagIsRecording_ tryClear])
    {
        return;
    }
    
    [movieWriter_ end];
    movieWriter_ = nil;
        
    // Start the auto off timer.
    [self startAutoOffTimer];
}

// Performs an auto focus at the specified point. The focus mode will automatically change to locked once the auto focus is
// complete.
- (void)autoFocusAtPoint:(CGPoint)point
{
    AVCaptureDevice * captureDevice = [captureDeviceInputVideo_ device];
    if ([captureDevice isFocusPointOfInterestSupported] && [captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        NSError * error;
        if ([captureDevice lockForConfiguration:&error])
        {
            [captureDevice setFocusPointOfInterest:point];
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            [captureDevice unlockForConfiguration];
        }
        else
        {
            [[self delegate] camcorder:self didFailWithError:error];
        }        
    }
}

// Switch to continuous auto focus mode at the specified point
- (void)continuousFocusAtPoint:(CGPoint)point
{
    AVCaptureDevice * device = [captureDeviceInputVideo_ device];
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
    {
		NSError * error;
		if ([device lockForConfiguration:&error])
        {
			[device setFocusPointOfInterest:point];
			[device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
			[device unlockForConfiguration];
		}
        else
        {
            [[self delegate] camcorder:self didFailWithError:error];
		}
	}
}

@end

// Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) implementation.
@implementation Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate)

// Called whenever an AVCaptureVideoDataOutput or AVCaptureAudioDataOutput instance has data.
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // Ignore data when not recording.
    if ([atomicFlagIsRecording_ isSet])
    {
        if (captureOutput == captureVideoDataOutput_)
        {
            [movieWriter_ processVideoSampleBuffer:sampleBuffer];
        }
        else if (captureOutput == captureAudioDataOutput_)
        {
            [movieWriter_ processAudioSampleBuffer:sampleBuffer];
        }
    }    
}

@end

// Camcorder (Internal) implementation.
@implementation Camcorder (Internal)

// Returns an AVCaptureConnection* matching the specified media type from the specified array of connections.
+ (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections
{
    for (AVCaptureConnection * connection in connections)
    {
        for (AVCaptureInputPort * port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:mediaType])
            {
                return connection;
            }
        }
    }
    
    return nil;
}

// Returns the camera with the specificed AVCaptureDevicePosition. If a camera with the specificed
// AVCaptureDevicePosition cannot be found, nil is returned.
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    NSArray * devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice * device in devices)
    {
        if ([device position] == position)
        {
            return device;
        }
    }
    
    return nil;
}

// Returns the first audio device, if it was found; otherwise, nil.
- (AVCaptureDevice *)audioDevice
{
    NSArray * devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
    {
        return [devices objectAtIndex:0];
    }
    
    return nil;
}

// AVCaptureDeviceWasConnectedNotification observer callback.
- (void)captureDeviceWasConnectedNotification:(NSNotification *)notification
{
    AVCaptureDevice * captureDevice = (AVCaptureDevice *)[notification object];
    
    BOOL sessionHasDeviceWithMatchingMediaType = NO;
    NSString * deviceMediaType = nil;
    if ([captureDevice hasMediaType:AVMediaTypeAudio])
    {
        deviceMediaType = AVMediaTypeAudio;
    }
    else if ([captureDevice hasMediaType:AVMediaTypeVideo])
    {
        deviceMediaType = AVMediaTypeVideo;
    }
    else
    {
        return;        
    }
    
    for (AVCaptureDeviceInput * captureDeviceInput in [captureSession_ inputs])
    {
        if ([[captureDeviceInput device] hasMediaType:deviceMediaType])
        {
            sessionHasDeviceWithMatchingMediaType = YES;
            break;
        }
    }
    
    if (!sessionHasDeviceWithMatchingMediaType)
    {
        NSError	*error;
        AVCaptureDeviceInput * captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
        if ([captureSession_ canAddInput:captureDeviceInput])
        {
            [captureSession_ addInput:captureDeviceInput];
        }
    }				
    
    // Notify the delegate.
    [[self delegate] camcorderDeviceConfigurationChanged:self];
}

// AVCaptureDeviceWasDisconnectedNotification observer callback.
- (void)captureDeviceWasDisconnectedNotification:(NSNotification *)notification
{
    // Process the notification.
    AVCaptureDevice * captureDevice = (AVCaptureDevice *)[notification object];    
    if ([captureDevice hasMediaType:AVMediaTypeAudio])
    {
        [captureSession_ removeInput:captureDeviceInputAudio_];
        captureDeviceInputAudio_ = nil;
    }
    else if ([captureDevice hasMediaType:AVMediaTypeVideo])
    {
        [captureSession_ removeInput:captureDeviceInputVideo_];
        captureDeviceInputVideo_ = nil;
    }
    
    // Notify the delegate.
    [[self delegate] camcorderDeviceConfigurationChanged:self];
}

// DirectrTurnOffVideoCameraNotification observer callback.
- (void)turnOffVideoCameraNotification:(NSNotification *)notification
{
    [self turnOff];
    [self stopAutoOffTimer];
}

// Auto off timer callback.
- (void)autoOffTimerCallback:(NSTimer *)timer
{
    // If we're not recording, turn the camcorder off.
    if ([atomicFlagIsRecording_ isClear])
    {
        NSLog(@"Auto-off.");
        [self turnOff];
    }  
}

// Recording timer callback.
- (void)recordingTimerCallback:(NSTimer *)timer
{
    // Call the delegate.
    //[[self videoCameraDelegate] videoCamera:self recordingElapsedTimeInterval:CMTimeGetSeconds([captureMovieFileOutput_ recordedDuration])];
}

@end
