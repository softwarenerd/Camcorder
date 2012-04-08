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

// Notifies the delegate that the camcorder did turn on.
- (void)camcorderDidTurnOn:(Camcorder *)camcorder;

// Notifies the delegate that the camcorder did turn off.
- (void)camcorderDidTurnOff:(Camcorder *)camcorder;

// Notifies the delegate that the camcorder did start recording.
- (void)camcorderDidStartRecording:(Camcorder *)camcorder;

// Notifies the delegate that the camcorder did finish recording.
- (void)camcorderFinishedRecording:(Camcorder *)camcorder videoFilePath:(NSString *)videoFilePath;

// Notifies the delegate of the recording elapsed time interval.
- (void)camcorder:(Camcorder *)camcorder recordingElapsedTimeInterval:(NSTimeInterval)recordingElapsedTimeInterval;

// Notifies the delegate that the camcorder device configuration changed.
- (void)camcorderDeviceConfigurationChanged:(Camcorder *)camcorder;

// Notifies the delegate that the camcorder failed with an error.
- (void)camcorder:(Camcorder *)camcorder didFailWithError:(NSError *)error;

@end