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

// Starts recording with an optional time interval.
- (void)doStartRecording:(NSTimeInterval *)timeInterval;

- (BOOL)setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription;

- (BOOL)setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription;

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
    
    // The sequence number.
    NSUInteger sequenceNumber_;
    
    // The camera resolution.
    CameraResolution cameraResolution_;
    
    // A value which indicates whether to capture audio.
    BOOL captureAudio_;
    
    // A value which indicates whether the video camera is on.
    AtomicFlag * atomicFlagIsOn_;
    
    // A value which indicates whether the video camera is recording.
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

    // The capture video data output queue. This queue is used by the
    // capture video data output above to deliver video buffers to our
    // AVCaptureVideoDataOutputSampleBufferDelegate implementation.
    dispatch_queue_t captureVideoDataOutputQueue_;
    
    // The capture audio data output queue. This queue is used by the
    // capture audi data output above to deliver audio buffers to our
    // AVCaptureAudioDataOutputSampleBufferDelegate implementation.
    dispatch_queue_t captureAudioDataOutputQueue_;

    // The asset writer queue.
    dispatch_queue_t assetWriterQueue_;
    
    // The video connection.
    AVCaptureConnection * videoConnection_;
    
    // The audio connection.
    AVCaptureConnection * audioConnection_;

    // The asset writer that writes the movie file.
    AVAssetWriter * assetWriter_;
    
    AVAssetWriterInput * assetWriterVideoIn_;
    AVAssetWriterInput * assetWriterAudioIn_;
    
    // Auto off timer.
    NSTimer * autoOffTimer_;
    
    // The timer used to fire videoCamera:recordingElapsedTimeInterval: callbacks to the VideoCameraDelegate.
    NSTimer * recordingTimer_;

    volatile BOOL readyToRecordVideo;
    volatile BOOL readyToRecordAudio;
}

// Gets or sets the delegate.
@synthesize delegate = delegate_;

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL 
          startingSequenceNumber:(NSUInteger)startingSequenceNumber
                cameraResolution:(CameraResolution)cameraResolution
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
    sequenceNumber_ = startingSequenceNumber;
    cameraResolution_ = cameraResolution;
    captureAudio_ = captureAudio;
    atomicFlagIsOn_ = [[AtomicFlag alloc] init];
    atomicFlagIsRecording_ = [[AtomicFlag alloc] init];
    
    // Create capture session.
    captureSession_ = [[AVCaptureSession alloc] init];
    
    // Set the capture session preset.
    switch (cameraResolution_)
    {
        case CameraResolution1920x1080:
            [captureSession_ setSessionPreset:AVCaptureSessionPreset1920x1080];
            break;
            
        case CameraResolution1280x720:
            [captureSession_ setSessionPreset:AVCaptureSessionPreset1280x720];
            break;

        case CameraResolution960x540:
            [captureSession_ setSessionPreset:AVCaptureSessionPresetiFrame960x540];
            break;

        default:
            captureSession_ = nil;
            @throw [NSException exceptionWithName:NSInvalidArgumentException
                                           reason:@"cameraPosition of CameraPositionNone may not be set."
                                         userInfo:nil];
    }
    
    // Create and add the capture video data output to the capture session.
    captureVideoDataOutput_ = [[AVCaptureVideoDataOutput alloc] init];
	[captureVideoDataOutput_ setAlwaysDiscardsLateVideoFrames:YES];
	captureVideoDataOutputQueue_ = dispatch_queue_create("co.directr.capv", DISPATCH_QUEUE_SERIAL);
	[captureVideoDataOutput_ setSampleBufferDelegate:self
                                               queue:captureVideoDataOutputQueue_];
    if ([captureSession_ canAddOutput:captureVideoDataOutput_])
    {
		[captureSession_ addOutput:captureVideoDataOutput_];
	}

    // If we're supposed to capture audio, create and add the capture audio data output to the capture session
    if (captureAudio_)
    {
        captureAudioDataOutput_ = [[AVCaptureAudioDataOutput alloc] init];
        captureAudioDataOutputQueue_ = dispatch_queue_create("co.directr.capa", DISPATCH_QUEUE_SERIAL);
        [captureAudioDataOutput_ setSampleBufferDelegate:self
                                                   queue:captureAudioDataOutputQueue_];
        if ([captureSession_ canAddOutput:captureAudioDataOutput_])
        {
            [captureSession_ addOutput:captureAudioDataOutput_];
        }
    }
    
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
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Unsupported capture device position."
                                         userInfo:nil];
    }    
}

// Sets the camera position.
- (void)setCameraPosition:(CameraPosition)cameraPosition
{
    // Set camera position to CameraPositionNone.
    if (cameraPosition == CameraPositionNone)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"cameraPosition of CameraPositionNone may not be set."
                                     userInfo:nil];
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
        // Can't get here unless a new entry is added to the enum and this code 
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

// Gets a value indicating whether the video camera is on.
- (BOOL)isOn
{
    return [atomicFlagIsOn_ isSet];
}

// Gets a value indicating whether the video camera is recording.
- (BOOL)isRecording
{
    return [atomicFlagIsRecording_ isSet];
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

// Turns the video camera off.
- (void)turnOff
{
    // If the camera is off, return.
    if ([atomicFlagIsOn_ tryClear])
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
    // Try to stop recording.
    if (![atomicFlagIsRecording_ tryClear])
    {
        return;
    }
    
    if ([assetWriter_ finishWriting])
    {
        assetWriterVideoIn_ = nil;        
        assetWriterAudioIn_ = nil;
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

// Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) implementation.
@implementation Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate)

- (void) writeSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(NSString *)mediaType
{
	if ( assetWriter_.status == AVAssetWriterStatusUnknown )
    {
        if ([assetWriter_ startWriting])
        {			
			[assetWriter_ startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
		}
		else {
            NSLog(@"Fuck1");
			//[self showError:[assetWriter_ error]];
		}
	}
	
	if ( assetWriter_.status == AVAssetWriterStatusWriting ) {
		
		if (mediaType == AVMediaTypeVideo) {
			if (assetWriterVideoIn_.readyForMoreMediaData) {
				if (![assetWriterVideoIn_ appendSampleBuffer:sampleBuffer]) {
                    NSLog(@"Fuck2");
					//[self showError:[assetWriter_ error]];
				}
			}
		}
		else if (mediaType == AVMediaTypeAudio) {
			if (assetWriterAudioIn_.readyForMoreMediaData) {
				if (![assetWriterAudioIn_ appendSampleBuffer:sampleBuffer]) {
                    NSLog(@"Fuck3");
					//[self showError:[assetWriter_ error]];
				}
			}
		}
	}
}

// Called whenever an AVCaptureVideoDataOutput or AVCaptureAudioDataOutput instance has data.
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // Ignore data when not recording.
    if ([atomicFlagIsRecording_ isClear])
    {
        return;
    }
    
    // Get the format description.
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);

    // Process sample buffer block.
    void (^processSampleBufferBlock)() = ^
    {
        // Enter writing mode, if we're not in writing mode.
        if ([assetWriter_ status] == AVAssetWriterStatusUnknown)
        {
            if ([assetWriter_ startWriting])
            {
                [assetWriter_ startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
            }
            else
            {
                NSLog(@"Fuck!");
                CFRelease(formatDescription);
                CFRelease(sampleBuffer);
                NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorUnableToStartAssetWriter userInfo:nil];
                [[self delegate] camcorder:self didFailWithError:error];
                [self stopRecording];
                return;
            }
        }

        // If we're in writing mode, write.
        if ([assetWriter_ status] == AVAssetWriterStatusWriting)
        {
            if (connection == videoConnection_)
            {
                if ([assetWriterVideoIn_ isReadyForMoreMediaData])
                {
                    if (![assetWriterVideoIn_ appendSampleBuffer:sampleBuffer])
                    {
                        NSLog(@"Unable to write video buffer!");
                    }
                }
            }
            else if (connection == audioConnection_)
            {
#if false
                if (!assetWriterAudioIn_)
                {
                    [self setupAssetWriterAudioInput:formatDescription];
                }
                

                if ([assetWriterAudioIn_ isReadyForMoreMediaData])
                {
                    if (![assetWriterAudioIn_ appendSampleBuffer:sampleBuffer])
                    {
                        NSLog(@"Unable to write audio buffer!");
                    }
                }
#endif
            }        
		}

        // Done.
		CFRelease(formatDescription);
		CFRelease(sampleBuffer);
    };
    
    // Dispatch the processing of the sample buffer to the asset writer queue.
    CFRetain(sampleBuffer);
    CFRetain(formatDescription);
	dispatch_async(assetWriterQueue_, processSampleBufferBlock);
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
        
    videoConnection_ = [captureVideoDataOutput_ connectionWithMediaType:AVMediaTypeVideo];
    if (captureAudio_)
    {
        audioConnection_ = [captureVideoDataOutput_ connectionWithMediaType:AVMediaTypeAudio];
    }
    
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
    NSString * clipName = [NSString stringWithFormat:@"Camcorder%i.mp4", sequenceNumber_++];
    
    // Set clip URL.
    NSURL * clipURL = [outputDirectoryURL_ URLByAppendingPathComponent:clipName];
    
    // Create the asset writer queue.
	assetWriterQueue_ = dispatch_queue_create("co.directr.assetwriterqueue", DISPATCH_QUEUE_SERIAL);
    
    // Create an asset writer
    NSError * error;
    assetWriter_ = [[AVAssetWriter alloc] initWithURL:clipURL fileType:(NSString *)kUTTypeMPEG4 error:&error];
    if (error)
    {
    }
    
    NSDictionary * compressionProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                            nil];
    
	NSDictionary * videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                               AVVideoCodecH264, AVVideoCodecKey,
                                               [NSNumber numberWithInteger:1920], AVVideoWidthKey,
                                               [NSNumber numberWithInteger:1080], AVVideoHeightKey,
                                               compressionProperties, AVVideoCompressionPropertiesKey,
                                               nil];
    
	if ([assetWriter_ canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) 
    {
		assetWriterVideoIn_ = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
		[assetWriterVideoIn_ setExpectsMediaDataInRealTime:YES];
		if ([assetWriter_ canAddInput:assetWriterVideoIn_])
        {
			[assetWriter_ addInput:assetWriterVideoIn_];
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


    // Set the recording flag.
    [atomicFlagIsRecording_ trySet];
}

- (BOOL)setupAssetWriterAudioInput:(CMFormatDescriptionRef)currentFormatDescription
{
	const AudioStreamBasicDescription *currentASBD = CMAudioFormatDescriptionGetStreamBasicDescription(currentFormatDescription);
    
	size_t aclSize = 0;
	const AudioChannelLayout * currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(currentFormatDescription, &aclSize);
	NSData * currentChannelLayoutData = nil;
	    
	// AVChannelLayoutKey must be specified, but if we don't know any better give an empty data and let AVAssetWriter decide.
	if (currentChannelLayout && aclSize > 0)
		currentChannelLayoutData = [NSData dataWithBytes:currentChannelLayout length:aclSize];
	else
		currentChannelLayoutData = [NSData data];
	
	NSDictionary *audioCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											  [NSNumber numberWithInteger:kAudioFormatMPEG4AAC], AVFormatIDKey,
											  [NSNumber numberWithFloat:currentASBD->mSampleRate], AVSampleRateKey,
											  [NSNumber numberWithInt:64000], AVEncoderBitRatePerChannelKey,
											  [NSNumber numberWithInteger:currentASBD->mChannelsPerFrame], AVNumberOfChannelsKey,
											  currentChannelLayoutData, AVChannelLayoutKey,
											  nil];
	if ([assetWriter_ canApplyOutputSettings:audioCompressionSettings forMediaType:AVMediaTypeAudio]) {
		assetWriterAudioIn_ = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioCompressionSettings];
		assetWriterAudioIn_.expectsMediaDataInRealTime = YES;
		if ([assetWriter_ canAddInput:assetWriterAudioIn_])
			[assetWriter_ addInput:assetWriterAudioIn_];
		else {
			NSLog(@"Couldn't add asset writer audio input.");
            return NO;
		}
	}
	else {
		NSLog(@"Couldn't apply audio output settings.");
        return NO;
	}
    
    return YES;
}

- (BOOL)setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription 
{
	CMVideoDimensions videoDimensions = CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
		
    NSDictionary * compressionProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                            nil];
    
	NSDictionary * videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                               AVVideoCodecH264, AVVideoCodecKey,
                                               [NSNumber numberWithInteger:videoDimensions.width], AVVideoWidthKey,
                                               [NSNumber numberWithInteger:videoDimensions.height], AVVideoHeightKey,
                                               compressionProperties, AVVideoCompressionPropertiesKey,
                                               nil];

	if ([assetWriter_ canApplyOutputSettings:videoCompressionSettings forMediaType:AVMediaTypeVideo]) 
    {
		assetWriterVideoIn_ = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
		[assetWriterVideoIn_ setExpectsMediaDataInRealTime:YES];
		if ([assetWriter_ canAddInput:assetWriterVideoIn_])
        {
			[assetWriter_ addInput:assetWriterVideoIn_];
		}
        else
        {
			NSLog(@"Couldn't add asset writer video input.");
            return NO;
		}
	}
	else
    {
		NSLog(@"Couldn't apply video output settings.");
        return NO;
	}
    

    return YES;
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
