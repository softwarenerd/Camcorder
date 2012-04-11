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
    CamcorderErrorAudioDeviceNotFound = 1001,
    CamcorderErrorVideoDeviceNotFound = 1002,
    CamcorderErrorAlreadyRecording = 1003,
    CamcorderErrorNotRecording = 1004,
    CamcorderErrorOutputVideoSettingsInvalid = 1005,
    CamcorderErrorOutputVideoInitializationFailed = 1006,
    CamcorderErrorOutputAudioSettingsInvalid = 1007,
    CamcorderErrorOutputAudioInitializationFailed = 1008,
    CamcorderErrorRecording = 1009,
    CamcorderErrorAddVideoInput = 1010,
    CamcorderErrorAddAudioInput = 1011,
    CamcorderErrorAddVideoOutput = 1012,
    CamcorderErrorAddAudioOutput = 1013
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
- (void)asyncTurnOnWithCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
                                       audio:(BOOL)audio;

// Asynchronously turns the camcorder off.
- (void)asyncTurnOff;

// Performs an auto focus at the specified point. The focus mode will
// automatically change to locked once the auto focus is complete.
- (void)autoFocusAtPoint:(CGPoint)point;

// Switch to continuous auto focus mode at the specified point
- (void)continuousFocusAtPoint:(CGPoint)point;

// Asynchronously starts recording.
- (void)asyncStartRecordingToOutputDirectoryURL:(NSURL *)outputDirectoryURL
                                          width:(NSUInteger)width
                                         height:(NSUInteger)height
                                          audio:(BOOL)audio
                                   timeInterval:(NSTimeInterval)timeInterval;

// Asynchronously stops recording.
- (void)asyncStopRecording;

@end
