//
//  Camcorder.m
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "libkern/OSAtomic.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/CGImageProperties.h>
#import "Camcorder.h"

// Camcorder (AVCaptureVideoDataOutputSampleBufferDelegate) interface.
@interface Camcorder (AVCaptureVideoDataOutputSampleBufferDelegate) <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

// Camcorder (AVCaptureFileOutputRecordingDelegate) interface.
@interface Camcorder (AVCaptureFileOutputRecordingDelegate) <AVCaptureFileOutputRecordingDelegate>

// Informs the delegate when the output has started writing to a file.
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections;

// 	Informs the delegate when all pending data has been written to an output file.
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error;

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

// Starts recording with an optional time interval.
- (void)doStartRecording:(NSTimeInterval *)timeInterval;

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
    
    // A value which indicates whether the video camera is on.
    volatile BOOL isOn_;
    
    // A value which indicates whether the video camera is recording.
    volatile BOOL isRecording_;
    
    // The capture session.
    AVCaptureSession * captureSession_;
    
    // The capture video preview layer.
    AVCaptureVideoPreviewLayer * captureVideoPreviewLayer_;

    // The video capture device input.
    AVCaptureDeviceInput * captureDeviceInputVideo_;
    
    // The audio capture device input.
    AVCaptureDeviceInput * captureDeviceInputAudio_;
    
    dispatch_queue_t videoCaptureQueue_;
    dispatch_queue_t movieWritingQueue_;
    
    AVCaptureVideoDataOutput * captureVideoDataOutput_;
    
    AVCaptureConnection * videoConnection_;
    
    AVAssetWriter * assetWriter_;
    
    AVAssetWriterInput * assetWriterVideoIn_;
    
    // Auto off timer.
    NSTimer * autoOffTimer_;
    
    // The timer used to fire videoCamera:recordingElapsedTimeInterval: callbacks to the VideoCameraDelegate.
    NSTimer * recordingTimer_;
}

// Gets or sets the delegate.
@synthesize delegate = delegate_;

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL
{
    // Initialize superclass.
    self = [super init];
    
    // Handle errors.
    if (!self)
    {
        return nil;
    }
    
    // Set the output directory URL.
    outputDirectoryURL_ = outputDirectoryURL;
    
    // Create capture session.
    captureSession_ = [[AVCaptureSession alloc] init];
    [captureSession_ setSessionPreset:AVCaptureSessionPreset1920x1080];
    
    // Create and add the capture video data output to the capture session.
    captureVideoDataOutput_ = [[AVCaptureVideoDataOutput alloc] init];
	[captureVideoDataOutput_ setAlwaysDiscardsLateVideoFrames:YES];
	videoCaptureQueue_ = dispatch_queue_create("co.directr.videocap", DISPATCH_QUEUE_SERIAL);
	[captureVideoDataOutput_ setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)self queue:videoCaptureQueue_];
    if ([captureSession_ canAddOutput:captureVideoDataOutput_])
    {
		[captureSession_ addOutput:captureVideoDataOutput_];
	}

    
    // Create serial queue for movie writing
	movieWritingQueue_ = dispatch_queue_create("co.directr.movewrite", DISPATCH_QUEUE_SERIAL);

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

// Gets the camera position.
- (CameraPosition)cameraPosition
{
    // If there is no video capture device input, return CameraPositionNone.
    if (!captureDeviceInputVideo_)
    {
        return CameraPositionNone;
    }
    
    // Process the video capture device input position.
    switch ([[captureDeviceInputVideo_ device] position])
    {
        // Back.
        case AVCaptureDevicePositionBack:
            return CameraPositionBack;

        // Front.
        case AVCaptureDevicePositionFront:
            return CameraPositionFront;

        // In theory we can't get here.
        default:
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Unsupported capture device position." userInfo:nil];
    }    
}

// Sets the camera position.
- (void)setCameraPosition:(CameraPosition)cameraPosition
{
    // Set camera position to CameraPositionNone.
    if (cameraPosition == CameraPositionNone)
    {
        // If we have a video capture device input, remove it.
        if (captureDeviceInputVideo_)
        {
            [captureSession_ beginConfiguration];
            [captureSession_ removeInput:captureDeviceInputVideo_];
            [captureSession_ commitConfiguration];
            captureDeviceInputVideo_ = nil;
        }
        
        // Done.
        return;
    }
    
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
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Unsupported camera position." userInfo:nil];
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

// Gets a value indicating whether the video camera is on.
- (BOOL)isOn
{
    return isOn_;
}

// Gets a value indicating whether the video camera is recording.
- (BOOL)isRecording
{
    return isRecording_;
}

// Returns a AVCaptureVideoPreviewLayer for the video camera.
- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer
{
    // Allocate the 
    if (!captureVideoPreviewLayer_)
    {
        captureVideoPreviewLayer_ = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession_];
    }
    
    return captureVideoPreviewLayer_;
}

// Turns the video camera on.
- (void)turnOn
{
    // Turn the video camera on, if it's off.
    if (!isOn_)
    {        
        // Set the flag.
        isOn_ = YES;
        
        // Start the session. This is done asychronously since -startRunning doesn't return until the
        // session is running.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                       ^{
                           // Start the capture session.
                           [captureSession_ startRunning];
                           
                           // Inform the delegate.
                           [[self delegate] camcorderTurnedOn:self];
                       });
    }
}

// Turns the video camera off.
- (void)turnOff
{
    // Turn the video camera off, if it's on.
    if (isOn_)
    {
        // Stops the auto off timer.
        [self stopAutoOffTimer];
        
        // Stop the session. This is done asychronously since -stopRunning doesn't return until the
        // session is running.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                       ^{
                           // Stop the capture session.
                           [captureSession_ stopRunning];
                           
                           // Clear the flag.
                           isOn_ = NO;
                           
                           // Inform the delegate that the camera has turned off.
                           [[self delegate] camcorderTurnedOff:self];
                       });
    }
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
    // Do it.
    [self doStartRecording:nil];
}

// Starts recording with a time interval.
- (void)startRecordingWithTimeInterval:(NSTimeInterval)timeInterval
{
    // Do it.
    [self doStartRecording:&timeInterval];
}

// Stops recording.
- (void)stopRecording
{
    // Set the recording flag.
    isRecording_ = NO;
    
    if ([assetWriter_ finishWriting])
    {
        assetWriterVideoIn_ = nil;
        assetWriter_ = nil;
    }
    
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

// Camcorder (AVCaptureVideoDataOutputSampleBufferDelegate) implementation.
@implementation Camcorder (AVCaptureVideoDataOutputSampleBufferDelegate)

- (void) writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
	if ([assetWriter_ status] == AVAssetWriterStatusUnknown)
    {
        if ([assetWriter_ startWriting])
        {			
			[assetWriter_ startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
		}
		else
        {
			NSLog(@"Fucker!");
		}
	}
	
	if ([assetWriter_ status] == AVAssetWriterStatusWriting )
    {
		if (mediaType == AVMediaTypeVideo)
        {
			if ([assetWriterVideoIn_ isReadyForMoreMediaData])
            {
				if (![assetWriterVideoIn_ appendSampleBuffer:sampleBuffer])
                {
                    NSLog(@"Fucker!");
				}
			}
		}
	}
}

// Called whenever an AVCaptureVideoDataOutput instance outputs a new video frame.
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
	CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    void (^work)() = ^
    {
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);

        //NSLog(@"Fuck! %i, %i %@", dimensions.width, dimensions.height, isRecording_ ? @"Recording" : @"Not recording");
		if (assetWriter_)
        {
            if (isRecording_)
            {
                if (connection == videoConnection_)
                {
                    [self writeSampleBuffer:sampleBuffer ofType:AVMediaTypeVideo];
                }
            }
		}

		CFRelease(sampleBuffer);
		CFRelease(formatDescription);
    };

    
    CFRetain(sampleBuffer);
	CFRetain(formatDescription);
	dispatch_async(movieWritingQueue_, work);
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

// Starts recording with an optional time interval.
- (void)doStartRecording:(NSTimeInterval *)timeInterval
{
    // Stop the auto off timer.
    [self stopAutoOffTimer];
        
#if false
    // Start the recording timer that emits videoCamera:recordingElapsedTimeInterval: calls to
    // the delegate.
    recordingTimer_ = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                       target:self
                                                     selector:@selector(recordingTimerCallback:)
                                                     userInfo:nil
                                                      repeats:YES];
#endif
    
    // Format the clip name.
    NSString * clipName = [NSString stringWithFormat:@"Movie.mov"];
    
    // Set clip URL.
    NSURL * clipURL = [outputDirectoryURL_ URLByAppendingPathComponent:clipName];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = [clipURL path];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError *error;
        [fileManager removeItemAtPath:filePath error:&error];
    }

    // Create an asset writer
    NSError * error;
    AVAssetWriter * assetWriter = [[AVAssetWriter alloc] initWithURL:clipURL fileType:(NSString *)kUTTypeMPEG4 error:&error];
    if (error)
    {
    }
    
    //AVCaptureSessionPreset1920x1080
	int numPixels = 1920 * 1080;
    CGFloat bitsPerPixel = 11.4;
    int bitsPerSecond = numPixels * bitsPerPixel;
    NSLog(@"BPS %i", bitsPerSecond);
    	
	NSDictionary * videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                               AVVideoCodecH264, AVVideoCodecKey,
                                               [NSNumber numberWithInteger:1920], AVVideoWidthKey,
                                               [NSNumber numberWithInteger:1080], AVVideoHeightKey,
                                               [NSDictionary dictionaryWithObjectsAndKeys:
											   //[NSNumber numberWithInteger:bitsPerSecond], AVVideoAverageBitRateKey,
											   [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
											   nil], AVVideoCompressionPropertiesKey,
											  nil];
	AVAssetWriterInput * assetWriterVideoIn;
    if ([assetWriter canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo])
    {
		assetWriterVideoIn = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
		[assetWriterVideoIn setExpectsMediaDataInRealTime:YES];
		//[assetWriterVideoIn setTransform:[self transformFromCurrentVideoOrientationToOrientation:self.referenceOrientation]];
		if ([assetWriter canAddInput:assetWriterVideoIn])
        {
			[assetWriter addInput:assetWriterVideoIn];
        }
		else
        {
			NSLog(@"Couldn't add asset writer video input.");
            return;
		}
	}
	else
    {
		NSLog(@"Couldn't apply video output settings.");
        return;
	}

    videoConnection_ = [captureVideoDataOutput_ connectionWithMediaType:AVMediaTypeVideo];

    assetWriter_ = assetWriter;
    assetWriterVideoIn_ = assetWriterVideoIn;
   
    // Set the recording flag.
    isRecording_ = YES;    
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
    // If we're not recording, turn the video camera off.
    if (!isRecording_)
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
