//
//  Camcorder.m
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 Brian Lambert. All rights reserved.
//

#import "libkern/OSAtomic.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import "AtomicFlag.h"
#import "Camcorder.h"
#import <AssetsLibrary/AssetsLibrary.h>

// Output queue name.
#define OUTPUT_QUEUE "camcorder.output"

// Asset writer queue name.
#define ASSET_WRITER_QUEUE "camcorder.writer"

// Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) interface.
@interface Camcorder (AVCaptureAudioVideoDataOutputSampleBufferDelegate) <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@end

// Camcorder (Internal) interface.
@interface Camcorder (Internal)

// Turns the camcorder on.
- (void)turnOnWithCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
                                  audio:(BOOL)audio;

// Turns the camcorder off.
- (void)turnOff;

// Starts recording.
- (void)startRecordingToOutputDirectoryURL:(NSURL *)outputDirectoryURL
                                     width:(NSUInteger)width
                                    height:(NSUInteger)height
                                     audio:(BOOL)audio
                              timeInterval:(NSTimeInterval)timeInterval;

// Stops recording.
- (void)stopRecording;

@end

// Camcorder implementation.
@implementation Camcorder
{
@private
    // A value which indicates whether we are performing an async operation.
    AtomicFlag * atomicFlagAsyncOperation_;

    // A value which indicates whether the camcorder is on.
    AtomicFlag * atomicFlagIsOn_;
        
    // A value which indicates whether the camcorder is recording.
    AtomicFlag * atomicFlagIsRecording_;
    
    // The capture session. All video and audio inputs and outputs are
    // connected to the capture session.
    AVCaptureSession * captureSession_;
    
    // The capture video preview layer that displays a preview of the
    // capture session. This is a singleton instance that is created
    // the first time it is asked for.
    AVCaptureVideoPreviewLayer * captureVideoPreviewLayer_;

    // The capture device input for video.
    AVCaptureDeviceInput * captureDeviceInputVideo_;
    
    // The capture device input for audio, which may be nil.
    AVCaptureDeviceInput * captureDeviceInputAudio_;
    
    // The capture video data output. Delivers video buffers to our 
    // AVCaptureVideoDataOutputSampleBufferDelegate implementation.
    AVCaptureVideoDataOutput * captureVideoDataOutput_;
    
    // The capture audio data output, which may be nil. Delivers audio
    // buffers to our AVCaptureVideoDataOutputSampleBufferDelegate
    // implementation.
    AVCaptureAudioDataOutput * captureAudioDataOutput_;

    // The capture output queue.
    dispatch_queue_t captureOutputQueue_;
              
    // The asset writer queue.
    dispatch_queue_t assetWriterQueue_;

    // A value which indicate whether the asset writer session has been started.
    AtomicFlag * atomicFlagAssetWriterSessionStarted_;
    
    // The asset writer that writes the movie file.
    AVAssetWriter * assetWriter_;
    
    // The asset writer video input.
    AVAssetWriterInput * assetWriterVideoInput_;
    
    // The asset writer audio input.
    AVAssetWriterInput * assetWriterAudioInput_;
    
    // The video file URL.
    NSURL * videoFileURL_;

    // The recording time interval. A value of 0.0 means a recording will stop
    // when stop.
    NSTimeInterval recordingTimeInterval_;

    // The recording start time.
    volatile CMTime assetWriterStartTime_;
    
    // The elapsed time interval.
    volatile NSTimeInterval recordingElapsedTimeInterval_;
}

// Class initializer.
- (id)init
{
    // Initialize superclass.
    self = [super init];
    
    // Handle errors.
    if (!self)
    {
        return nil;
    }
    
    // Initialize.
    atomicFlagAsyncOperation_ = [[AtomicFlag alloc] init];
    atomicFlagIsOn_ = [[AtomicFlag alloc] init];
    atomicFlagIsRecording_ = [[AtomicFlag alloc] init];
    atomicFlagAssetWriterSessionStarted_ = [[AtomicFlag alloc] init]; 
    captureOutputQueue_ = dispatch_queue_create(OUTPUT_QUEUE, DISPATCH_QUEUE_SERIAL);
    assetWriterQueue_ = dispatch_queue_create(ASSET_WRITER_QUEUE, DISPATCH_QUEUE_SERIAL);
    
    // Allocate the capture session here so that layers above this layer can
    // get a AVCaptureVideoPreviewLayer through the captureVideoPreviewLayer
    // property. Inputs and outputs are added to and removed from the capture
    // session when the camcorder is turned on and off.
    captureSession_ = [[AVCaptureSession alloc] init];

    // Done.
    return self;
}

// Dealloc.
- (void)dealloc
{
    dispatch_release(captureOutputQueue_);
    dispatch_release(assetWriterQueue_);
}

// Gets or sets the delegate.
@synthesize delegate = delegate_;

// Gets the capture video preview layer. It is safe to get this at any time.
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

// Gets the recording elapsed time interval.
- (NSTimeInterval)recordingElapsedTimeInterval
{
    return recordingElapsedTimeInterval_;
}

// Asynchronously turns the camcorder on. If the camcorder is on, it is turned off then on.
- (void)asyncTurnOnWithCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
                                                audio:(BOOL)audio
{
    // Turn camcorder on block.
    void (^turnCamcorderOnBlock)() = ^
    {
        [self turnOnWithCaptureDevicePosition:captureDevicePosition audio:audio];        
        [atomicFlagAsyncOperation_ tryClear];
    };

    // Only one asynchronous operation at a time.
    if ([atomicFlagAsyncOperation_ trySet])
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), turnCamcorderOnBlock);
    }
}

// Asynchronously turns the camcorder off.
- (void)asyncTurnOff
{
    // Turn camcorder off block.
    void (^turnCamcorderOffBlock)() = ^
    {
        [self turnOff];
        [atomicFlagAsyncOperation_ tryClear];
    };

    // Only one asynchronous operation at a time.
    if ([atomicFlagAsyncOperation_ trySet])
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), turnCamcorderOffBlock);
    }
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
    AVCaptureDevice * captureDevice = [captureDeviceInputVideo_ device];
    if ([captureDevice isFocusPointOfInterestSupported] && [captureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
    {
		NSError * error;
		if ([captureDevice lockForConfiguration:&error])
        {
			[captureDevice setFocusPointOfInterest:point];
			[captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
			[captureDevice unlockForConfiguration];
		}
        else
        {
            [[self delegate] camcorder:self didFailWithError:error];
		}
	}
}

// Starts recording with an optional time interval.
- (void)asyncStartRecordingToOutputDirectoryURL:(NSURL *)outputDirectoryURL
                                                   width:(NSUInteger)width
                                                  height:(NSUInteger)height
                                                   audio:(BOOL)audio
                                            timeInterval:(NSTimeInterval)timeInterval
{
    // Start recording block.
    void (^startRecordingBlock)() = ^
    {
        [self startRecordingToOutputDirectoryURL:outputDirectoryURL
                                           width:width
                                          height:height
                                           audio:audio
                                    timeInterval:timeInterval];
        [atomicFlagAsyncOperation_ tryClear];
    };
    
    // Only one asynchronous operation at a time.
    if ([atomicFlagAsyncOperation_ trySet])
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), startRecordingBlock);
    }
}

// Stops recording.
- (void)asyncStopRecording
{
    // Start recording block.
    void (^startRecordingBlock)() = ^
    {
        [self stopRecording];
        [atomicFlagAsyncOperation_ tryClear];
    };
    
    // Only one asynchronous operation at a time.
    if ([atomicFlagAsyncOperation_ trySet])
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), startRecordingBlock);
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
    if ([atomicFlagIsRecording_ isClear])
    {
        return;
    }
    
    // Process sample buffer block.
    void (^processSampleBufferBlock)() = ^
    {
        // Ignore samples that arrive after we stop recording.
        if ([atomicFlagIsRecording_ isClear])
        {
            return;
        }
        
        // Get the sample timestamp.
        CMTime timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        // If this is the first sample buffer, start the asset writer session.
        if ([atomicFlagAssetWriterSessionStarted_ trySet])
        {
            assetWriterStartTime_ = timeStamp;
            [assetWriter_ startSessionAtSourceTime:assetWriterStartTime_];
        }
        
        // Calculate the elapsed time interval.
        NSTimeInterval elapsedTimeInterval = CMTimeGetSeconds(CMTimeSubtract(timeStamp, assetWriterStartTime_));

        // If we're writing, write.
        if ([assetWriter_ status] == AVAssetWriterStatusWriting)
        {
            // Process the audio or video sample.
            if (captureOutput == captureAudioDataOutput_)
            {
                // If the asset writer input is ready for data, append it.
                if ([assetWriterAudioInput_ isReadyForMoreMediaData])
                {
                    [assetWriterAudioInput_ appendSampleBuffer:sampleBuffer];
                }
            }
            else if (captureOutput == captureVideoDataOutput_)
            {
                // If the asset writer input is ready for data, append it.
                if ([assetWriterVideoInput_ isReadyForMoreMediaData])
                {
                    [assetWriterVideoInput_ appendSampleBuffer:sampleBuffer];
                }
                
                // End timed recording. We use video samples to determine this.
                if (recordingTimeInterval_ != 0.0 && elapsedTimeInterval >= recordingTimeInterval_)
                {
                    elapsedTimeInterval = recordingTimeInterval_;
                    [self stopRecording];
                }
            }
        }
        
        // Update the elapsed time interval.
        recordingElapsedTimeInterval_ = elapsedTimeInterval;

        // Done.
        CFRelease(sampleBuffer);
    };
    
    // Retain prior to dispatch.
    CFRetain(sampleBuffer);
    
    // Dispatch the processing of the sample buffer to the asset writer queue.
    dispatch_async(assetWriterQueue_, processSampleBufferBlock);                
}

@end

// Camcorder (Internal) implementation.
@implementation Camcorder (Internal)

// Turns the camcorder on. If the camcorder is on, it is turned off then on.
- (void)turnOnWithCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
                                  audio:(BOOL)audio
{
    // Turn off.
    [self turnOff];

    // Find the first video capture device with the specified positon.
    AVCaptureDevice * captureDevice = nil;
    for (AVCaptureDevice * captureDeviceCheck in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
    {
        if ([captureDeviceCheck position] == captureDevicePosition)
        {
            captureDevice =  captureDeviceCheck;
            break;
        }
    }
    
    // If a video capture device with the specified positon could not be found, we're done.
    if (captureDevice == nil)
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorVideoDeviceNotFound userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
    
    // Allocate the video capture device input for the video capture device.
    NSError * error;
    AVCaptureDeviceInput * captureDeviceInputVideo = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
    if (error)
    {
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
    
    // See if we can add the video capture device input to the capture session.
    if (![captureSession_ canAddInput:captureDeviceInputVideo])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAddVideoInput userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
    
    // Handle audiop, if we should.
    AVCaptureDeviceInput * captureDeviceInputAudio;
    if (!audio)
    {
        captureDeviceInputAudio = nil;
    }
    else
    {
        // Get the default audio capture device.
        AVCaptureDevice * audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        
        // If an audio capture device could not be found, we're done.
        if (audioDevice == nil)
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAudioDeviceNotFound userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
        
        // Allocate the audio capture device input for the audio capture device.
        NSError * error;
        captureDeviceInputAudio = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:&error];
        if (error)
        {
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
        
        // See if we can add the audio capture device input to the capture session.
        if (![captureSession_ canAddInput:captureDeviceInputAudio])
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAddAudioInput userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
    }
    
    // Create the capture video data output.
    AVCaptureVideoDataOutput * captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [captureVideoDataOutput setAlwaysDiscardsLateVideoFrames:NO];
    [captureVideoDataOutput setSampleBufferDelegate:self queue:captureOutputQueue_];
        
    // If we can't add the video output, report the failure 
    if (![captureSession_ canAddOutput:captureVideoDataOutput])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAddVideoOutput userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
    
    // Create the capture audio data output.
    AVCaptureAudioDataOutput * captureAudioDataOutput;
    if (!audio)
    {
        captureAudioDataOutput = nil;
    }
    else
    {
        captureAudioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        [captureAudioDataOutput setSampleBufferDelegate:self queue:captureOutputQueue_];
        
        if (![captureSession_ canAddOutput:captureAudioDataOutput])
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAddAudioOutput userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
    }
    
    // Add inputs.
    [captureSession_ addInput:captureDeviceInputVideo];
    if (captureDeviceInputAudio)
    {
        [captureSession_ addInput:captureDeviceInputAudio];            
    }
    
    // Add outputs.
    [captureSession_ addOutput:captureVideoDataOutput];
    if (captureAudioDataOutput)
    {
        [captureSession_ addOutput:captureAudioDataOutput];            
    }
    
    // Set context.
    captureDeviceInputVideo_ = captureDeviceInputVideo;
    captureDeviceInputAudio_ = captureDeviceInputAudio;
    captureVideoDataOutput_ = captureVideoDataOutput; 
    captureAudioDataOutput_ = captureAudioDataOutput; 
        
    // Start the capture session running.
    [captureSession_ startRunning];
    
    // Set the on flag.
    [atomicFlagIsOn_ trySet];
    
    // Inform the delegate.
    [[self delegate] camcorderDidTurnOn:self];      
}

// Turns the camcorder off.
- (void)turnOff
{
    // If the camcorder is not on, return.
    if ([atomicFlagIsOn_ isClear])
    {
        return;
    }
        
    [self stopRecording];
    
    // Stop the capture session.
    [captureSession_ stopRunning];
    
    // Remove inputs;
    [captureSession_ removeInput:captureDeviceInputVideo_];
    if (captureDeviceInputAudio_)
    {
        [captureSession_ removeInput:captureDeviceInputAudio_];                
    }

    // Remove outputs.
    [captureSession_ removeOutput:captureVideoDataOutput_];
    if (captureAudioDataOutput_)
    {
        [captureSession_ removeOutput:captureAudioDataOutput_];
    }

    // Clear context.
    captureDeviceInputVideo_ = nil;
    captureDeviceInputAudio_ = nil;
    captureVideoDataOutput_ = nil;
    captureAudioDataOutput_ = nil;
    
    // Clear the on flag.
    [atomicFlagIsOn_ tryClear];
    
    // Inform the delegate.
    [[self delegate] camcorderDidTurnOff:self];
}

// Starts recording.
- (void)startRecordingToOutputDirectoryURL:(NSURL *)outputDirectoryURL
                                                   width:(NSUInteger)width
                                                  height:(NSUInteger)height
                                                   audio:(BOOL)audio
                                            timeInterval:(NSTimeInterval)timeInterval
{
    // If the camcorder isn't on, we can't start recording.
    if ([atomicFlagIsOn_ isClear])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorNotTurnedOn userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];        
        return;
    }

    // If we're already recording, we can't start recording.
    if ([atomicFlagIsRecording_ isSet])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorAlreadyRecording userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
       
    // Set-up the date formatter string used to construct the video file name.
    NSDateFormatter * dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyy-MM-dd-HH:mm:ss:SS"];
    
    // Format the video file name.
    NSString * videoFileName = [NSString stringWithFormat:@"Camcorder-%@.mp4", [dateFormat stringFromDate:[[NSDate alloc] init]]];
    
    // Set video file URL.
    videoFileURL_ = [outputDirectoryURL URLByAppendingPathComponent:videoFileName];
    
    // Create the asset writer
    NSError * error;
    AVAssetWriter * assetWriter = [[AVAssetWriter alloc] initWithURL:videoFileURL_ fileType:(NSString *)kUTTypeMPEG4 error:&error];
    if (error)
    {
        [[self delegate] camcorder:self didFailWithError:error];        
        return;
    }
    
    // Set-up the transform for the asset writer.
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    AVCaptureDevicePosition captureDevicePosition = [[captureDeviceInputVideo_ device] position];
    CGAffineTransform affineTransform = CGAffineTransformMakeRotation(0.0);
    if (captureDevicePosition == AVCaptureDevicePositionBack)
    {
        if (deviceOrientation == UIDeviceOrientationLandscapeRight)
        {
            affineTransform = CGAffineTransformMakeRotation(M_PI);            
        }
    }
    else if (captureDevicePosition == AVCaptureDevicePositionFront)
    {
        if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
        {
            affineTransform = CGAffineTransformMakeRotation(M_PI);             
        }
    }
    
    // Experimental.
    float bitsPerPixel;
	int pixelsPerFrame = width * height;
	int bitsPerSecond;
	bitsPerPixel = 0.5; // 11.4
	bitsPerSecond = pixelsPerFrame * bitsPerPixel;
        
    // Create the compression properties.
    NSDictionary * compressionProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                            //[NSNumber numberWithInteger:bitsPerSecond], AVVideoAverageBitRateKey,
                                            nil];
    
    // Create the output settings.
	NSDictionary * outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                     AVVideoCodecH264, AVVideoCodecKey,
                                     [NSNumber numberWithInteger:width], AVVideoWidthKey,
                                     [NSNumber numberWithInteger:height], AVVideoHeightKey,
                                     compressionProperties, AVVideoCompressionPropertiesKey,
                                     nil];
    
    // See if the asset writer can apply the output settings.
	if (![assetWriter canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeVideo])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorOutputVideoSettingsInvalid userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
    
    // Allocate and initialize the asset writer video input.
    AVAssetWriterInput * assetWriterVideoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    [assetWriterVideoInput setTransform:affineTransform];
    [assetWriterVideoInput setExpectsMediaDataInRealTime:YES];    
    if (![assetWriter canAddInput:assetWriterVideoInput])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorOutputVideoInitializationFailed userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;
    }
        
    // If writing audio, initialize the asset writer audio intput.
    AVAssetWriterInput * assetWriterAudioInput;
    if (!audio)
    {
        assetWriterAudioInput = nil;
    }
    else
    {
        // Create the output settings.
        NSDictionary * outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithInteger:kAudioFormatMPEG4AAC], AVFormatIDKey,
                                         [NSNumber numberWithFloat:44100], AVSampleRateKey,
                                         [NSNumber numberWithInt:64000], AVEncoderBitRatePerChannelKey,
                                         [NSNumber numberWithInteger:1], AVNumberOfChannelsKey,
                                         [NSData data], AVChannelLayoutKey,
                                         nil];
        
        // See if the asset writer can apply the output settings.
        if (![assetWriter canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeAudio])
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorOutputAudioSettingsInvalid userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
        
        // Allocate and initialize the asset writer video input.
        assetWriterAudioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
        [assetWriterAudioInput setExpectsMediaDataInRealTime:YES];
        if (![assetWriter canAddInput:assetWriterAudioInput])
        {
            NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorOutputAudioInitializationFailed userInfo:nil];
            [[self delegate] camcorder:self didFailWithError:error];
            return;
        }
    }  

    // Add the asset writer inputs.
    [assetWriter addInput:assetWriterVideoInput];
    if (assetWriterAudioInput)
    {
        [assetWriter addInput:assetWriterAudioInput];
    }
        
    // Start writing.
    if (![assetWriter startWriting])
    {
        NSError * error = [NSError errorWithDomain:CamcorderErrorDomain code:CamcorderErrorRecording userInfo:nil];
        [[self delegate] camcorder:self didFailWithError:error];
        return;        
    }

    // Set-up context.
    recordingTimeInterval_ = timeInterval;
    assetWriter_ = assetWriter;
    assetWriterAudioInput_ = assetWriterAudioInput;
    assetWriterVideoInput_ = assetWriterVideoInput;

    // Set the recording flag.
    [atomicFlagIsRecording_ trySet];
        
    // Inform the delegate.
    [[self delegate] camcorderDidStartRecording:self];
}

// Stops recording.
- (void)stopRecording
{
    // If we're not recording, we can't stop recording.
    if ([atomicFlagIsRecording_ isClear])
    {
        return;
    }
    
    // Stop recording.
    [atomicFlagIsRecording_ tryClear];
    
    // Finish writing.
    [assetWriter_ finishWriting];
    
    // Inform the delegate.
    if (recordingTimeInterval_ != 0.0)
    {
        recordingElapsedTimeInterval_ = recordingTimeInterval_;
    }

    // Clear context.
    assetWriter_ = nil;
    assetWriterAudioInput_ = nil;
    assetWriterVideoInput_ = nil;
    [atomicFlagAssetWriterSessionStarted_ tryClear];

    // Test code.
    ALAssetsLibrary * library = [[ALAssetsLibrary alloc] init];
    [library writeVideoAtPathToSavedPhotosAlbum:videoFileURL_
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                    
                                }];
    
    // Inform the delegate.
    [[self delegate] camcorderDidStopRecording:self
                  recordingElapsedTimeInterval:recordingElapsedTimeInterval_
                                 videoFilePath:[videoFileURL_ path]];
    
}

@end
