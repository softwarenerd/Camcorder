//
//  MovieWriter.m
//  Camcorder
//
//  Created by Brian Lambert on 4/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "MovieWriter.h"
#import "libkern/OSAtomic.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <ImageIO/CGImageProperties.h>
#import "AtomicFlag.h"

// MovieWriter implementation.
@implementation MovieWriter
{
@private
    NSError * error_;
        
    // The output directory URL. 
    NSURL * outputDirectoryURL_;
    
    // The video file URL.
    NSURL * videoFileURL_;
    
    // Width.
    NSUInteger width_;
    
    // Height.
    NSUInteger height_;

    // A value which indicates whether audio will be written..
    BOOL audio_;

    // A value which indicate whether the session has been started.
    AtomicFlag * atomicFlagSessionStarted_;
    
    // The asset writer queue.
    dispatch_queue_t assetWriterQueue_;
    
    // The asset writer that writes the movie file.
    AVAssetWriter * assetWriter_;
    
    // The asset writer video input.
    AVAssetWriterInput * assetWriterVideoInput_;
    
    // The asset writer audio input.
    AVAssetWriterInput * assetWriterAudioInput_;
}

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                           audio:(BOOL)audio
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
    audio_ = audio;
    atomicFlagSessionStarted_ = [[AtomicFlag alloc] init];
    
    // Done.
    return self;
}

- (void)dealloc
{
    NSLog(@"DEALLOC MovieWriter");
}

// Begins the movie writer.
- (BOOL)begin
{
    // Set-up the date formatter string used to construct the video file name.
    NSDateFormatter * dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyy-MM-dd-HH:mm:ss:SS"];
    
    // Format the video file name.
    NSString * videoFileName = [NSString stringWithFormat:@"Camcorder-%@.mp4", [dateFormat stringFromDate:[[NSDate alloc] init]]];
    
    // Set video file URL.
    videoFileURL_ = [outputDirectoryURL_ URLByAppendingPathComponent:videoFileName];
       
    // Create the asset writer
    NSError * error;
    assetWriter_ = [[AVAssetWriter alloc] initWithURL:videoFileURL_ fileType:(NSString *)kUTTypeMPEG4 error:&error];
    if (error)
    {
        error_ = error;
        return NO;
    }
    
    // Adjust for orientation.
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    CGAffineTransform affineTransform;
    if (UIDeviceOrientationIsPortrait(deviceOrientation))
    {
        affineTransform = CGAffineTransformMakeRotation(0.0);
    }
    else if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
    {
        NSLog(@"UIDeviceOrientationLandscapeLeft");
        //affineTransform = CGAffineTransformMakeRotation(-M_PI_2);
        affineTransform = CGAffineTransformMakeRotation(0.0);
    }
    else if (deviceOrientation == UIDeviceOrientationLandscapeRight)
    {
        NSLog(@"UIDeviceOrientationLandscapeRight");
        affineTransform = CGAffineTransformMakeRotation(M_PI);
        //affineTransform = CGAffineTransformMakeRotation(M_PI_2);
    }
    
    // Create the compression properties.
    NSDictionary * compressionProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                            nil];
    
    // Create the output settings.
	NSDictionary * outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                     AVVideoCodecH264, AVVideoCodecKey,
                                     [NSNumber numberWithInteger:width_], AVVideoWidthKey,
                                     [NSNumber numberWithInteger:height_], AVVideoHeightKey,
                                     compressionProperties, AVVideoCompressionPropertiesKey,
                                     nil];
    
    // See if the asset writer can apply the output settings.
	if (![assetWriter_ canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeVideo])
    {
        NSLog(@"assetWriter could not apply output settings");
        return NO;
    }
    
    // Allocate and initialize the asset writer video input.
    assetWriterVideoInput_ = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    [assetWriterVideoInput_ setTransform:affineTransform];
    [assetWriterVideoInput_ setExpectsMediaDataInRealTime:YES];    
    if (![assetWriter_ canAddInput:assetWriterVideoInput_])
    {
        NSLog(@"assetWriter could not add asset writer for video.");
        return NO;
    }

    // Add the asset writer video input.
    [assetWriter_ addInput:assetWriterVideoInput_];
    
    // If writing audio, initialize the asset writer audio intput. 
    if (audio_)
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
        if (![assetWriter_ canApplyOutputSettings:outputSettings forMediaType:AVMediaTypeAudio])
        {
            return NO;
        }

        // Allocate and initialize the asset writer video input.
        assetWriterAudioInput_ = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
        [assetWriterAudioInput_ setExpectsMediaDataInRealTime:YES];
        if (![assetWriter_ canAddInput:assetWriterAudioInput_])
        {
            return NO;
        }

        // Add the asset writer audio input.
        [assetWriter_ addInput:assetWriterAudioInput_];
    }  
    
    // Create the asset writer queue.
	assetWriterQueue_ = dispatch_queue_create("assetwriterqueue", DISPATCH_QUEUE_SERIAL);
    
    return [assetWriter_ startWriting];

    // Success!
    return YES;
}

// Ends the movie writer.
- (BOOL)end
{
    [assetWriter_ finishWriting];

    ALAssetsLibrary * library = [[ALAssetsLibrary alloc] init];
    [library writeVideoAtPathToSavedPhotosAlbum:videoFileURL_
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                   
                                }];
    
    dispatch_release(assetWriterQueue_);
    return YES;
}

// Processes a audio sample buffer.
- (void)processAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // If not writing audio, ignore the sample buffer.
    if (!audio_)
    {
        return;
    }
    
    // Process sample buffer block.
    void (^processSampleBufferBlock)() = ^
    {
        if ([atomicFlagSessionStarted_ trySet])
        {
            [assetWriter_ startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        }
 
        if ([assetWriter_ status] == AVAssetWriterStatusWriting && [assetWriterAudioInput_ isReadyForMoreMediaData])
        {
            if (![assetWriterAudioInput_ appendSampleBuffer:sampleBuffer])
            {
                NSLog(@"Unable to write audio buffer!");
            }
        }

        // Done.
		CFRelease(sampleBuffer);
    };

    // Retain prior to dispatch.
    CFRetain(sampleBuffer);
	
    // Dispatch the processing of the sample buffer to the asset writer queue.
    dispatch_async(assetWriterQueue_, processSampleBufferBlock);
}

// Processes a video sample buffer.
- (void)processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // Process sample buffer block.
    void (^processSampleBufferBlock)() = ^
    {
        if ([atomicFlagSessionStarted_ trySet])
        {
            [assetWriter_ startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        }

        if ([assetWriter_ status] == AVAssetWriterStatusWriting && [assetWriterVideoInput_ isReadyForMoreMediaData])
        {
            if (![assetWriterVideoInput_ appendSampleBuffer:sampleBuffer])
            {
                NSLog(@"Unable to write video buffer!");
            }
        }
        
        // Done.
		CFRelease(sampleBuffer);
    };
    
    // Retain prior to dispatch.
    CFRetain(sampleBuffer);
	
    // Dispatch the processing of the sample buffer to the asset writer queue.
    dispatch_async(assetWriterQueue_, processSampleBufferBlock);
}

@end
