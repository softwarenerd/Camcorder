//
//  MovieWriter.h
//  Camcorder
//
//  Created by Brian Lambert on 4/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// MovieWriter interface.
@interface MovieWriter : NSObject

// Class initializer.
- (id)initWithOutputDirectoryURL:(NSURL *)outputDirectoryURL
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                           audio:(BOOL)audio;

// Begins the movie writer.
- (BOOL)begin;

// Ends the movie writer.
- (BOOL)end;

// Processes a audio sample buffer.
- (void)processAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

// Processes a video sample buffer.
- (void)processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
