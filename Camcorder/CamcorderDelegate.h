//
//  CamcorderDelegate.h
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

// Forward declarations.
@class Camcorder;

// CamcorderDelegate protocol.
@protocol CamcorderDelegate <NSObject>
@required

// Camcorder turned on.
- (void)camcorderTurnedOn:(Camcorder *)camcorder;

// Camcorder turned off.
- (void)camcorderTurnedOff:(Camcorder *)camcorder;

// Camcorder started recording.
- (void)camcorderStartedRecording:(Camcorder *)camcorder;

// Camcorder finished recording.
- (void)camcorderFinishedRecording:(Camcorder *)camcorder videoFilePath:(NSString *)videoFilePath;

// Current recording elapsed time interval.
- (void)camcorder:(Camcorder *)camcorder recordingElapsedTimeInterval:(NSTimeInterval)recordingElapsedTimeInterval;

// Camcorder device configuration changed.
- (void)camcorderDeviceConfigurationChanged:(Camcorder *)camcorder;

// Camcorder failed with an error.
- (void)camcorder:(Camcorder *)camcorder didFailWithError:(NSError *)error;

@end