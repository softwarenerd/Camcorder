//
//  Camcorder.h
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "CamcorderDelegate.h"

// Camcorder error domain.
static NSString * CamcorderErrorDomain = @"Camcorder";

// Camcorder error code enumeration.
enum CamcorderErrorCode
{
    CamcorderErrorNotTurnedOn = 1000,
    CamcorderErrorAlreadyRecording = 1001,
    CamcorderErrorNotRecording = 1002,
    CamcorderErrorRecording = 1003,
    CamcorderErrorAddVideoInput = 1004,
    CamcorderErrorAddAudioInput = 1005,
    CamcorderErrorAddVideoOutput = 1006,
    CamcorderErrorAddAudioOutput = 1007,
};
typedef enum CamcorderErrorCode CamcorderErrorCode;

// Camcorder interface.
@interface Camcorder : NSObject

// Gets or sets the delegate.
@property (atomic, assign) id <CamcorderDelegate> delegate;

// Returns a AVCaptureVideoPreviewLayer for the camcorder.
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer * captureVideoPreviewLayer;

// Gets a value indicating whether the camcorder is on.
@property (nonatomic, readonly) BOOL isOn;

// Gets a value indicating whether the camcorder is recording.
@property (nonatomic, readonly) BOOL isRecording;

// Gets a value indicating whether the camcorder is recording.
@property (nonatomic, readonly) NSTimeInterval recordingElapsedTimeInterval;

// Asynchronously turns the camcorder on. If the camcorder is on, it is turned off then on.
- (void)asynchronouslyTurnOnWithCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
                                            audio:(BOOL)audio;

// Asynchronously turns the camcorder off.
- (void)asynchronouslyTurnOff;

// Performs an auto focus at the specified point. The focus mode will
// automatically change to locked once the auto focus is complete.
- (void)autoFocusAtPoint:(CGPoint)point;

// Switch to continuous auto focus mode at the specified point
- (void)continuousFocusAtPoint:(CGPoint)point;

// Asynchronously starts recording.
- (void)asynchronouslyStartRecordingToOutputDirectoryURL:(NSURL *)outputDirectoryURL
                                                   width:(NSUInteger)width
                                                  height:(NSUInteger)height
                                                   audio:(BOOL)audio
                                            timeInterval:(NSTimeInterval)timeInterval;

// Asynchronously stops recording.
- (void)asynchronouslyStopRecording;

@end
