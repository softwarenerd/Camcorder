//
//  Camcorder.h
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "libkern/OSAtomic.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "CamcorderDelegate.h"

// Camcorder error domain.
static NSString * CamcorderErrorDomain = @"Camcorder";

// Camcorder error code enumeration.
enum CamcorderErrorCode
{
    CamcorderErrorCodeNoVideoInput = 1001,
    CamcorderErrorUnableToAddAssetWriterVideoInput = 1002,
    CamcorderErrorUnableToStartAssetWriter = 1003
};
typedef enum CamcorderErrorCode CamcorderErrorCode;

// The camera position enumeration.
enum CameraPosition
{
    CameraPositionNone = 0,
    CameraPositionFront = 1,
    CameraPositionBack = 2
};
typedef enum CameraPosition CameraPosition;

// The camera resolution enumeration.
enum CameraResolution
{
    CameraResolution1920x1080 = 1,
    CameraResolution1280x720 = 2,
    CameraResolution960x540 = 3
};
typedef enum CameraResolution CameraResolution;

// Camcorder interface.
@interface Camcorder : NSObject

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                    captureAudio:(BOOL)captureAudio;

// Gets or sets the delegate.
@property (nonatomic, assign) id <CamcorderDelegate> delegate;

// Gets or sets the camera position.
@property (nonatomic, assign) CameraPosition cameraPosition;

// Gets a value indicating whether the video camera is on.
@property (nonatomic, readonly) BOOL isOn;

// Gets a value indicating whether the video camera is recording.
@property (nonatomic, readonly) BOOL isRecording;

// Returns a AVCaptureVideoPreviewLayer for the video camera.
- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer;

// Turns the video camera on.
- (void)turnOn;

// Turns the video camera off.
- (void)turnOff;

// Starts the auto off timer.
- (void)startAutoOffTimer;

// Stops the auto off timer.
- (void)stopAutoOffTimer;

// Starts recording.
- (void)startRecording;

// Starts recording with an optional time interval.
- (void)startRecordingWithTimeInterval:(NSTimeInterval *)timeInterval;

// Stops recording.
- (void)stopRecording;

// Performs an auto focus at the specified point. The focus mode will
//automatically change to locked once the auto focus is complete.
- (void)autoFocusAtPoint:(CGPoint)point;

// Switch to continuous auto focus mode at the specified point
- (void)continuousFocusAtPoint:(CGPoint)point;

@end
