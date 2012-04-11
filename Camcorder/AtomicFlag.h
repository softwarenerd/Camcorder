//
//  AtomicFlag.h
//
//  Created by Brian Lambert on 3/21/12.
//  Copyright (c) 2012 Brian Lambert. All rights reserved.
//

#import <UIKit/UIKit.h>

// AtomicFlag interface.
@interface AtomicFlag : NSObject

// Returns YES, if the flag is clear; otherwise, NO.
- (BOOL)isClear;

// Returns YES, if the flag is set; otherwise, NO.
- (BOOL)isSet;

// Tries to set the flag. Returns YES, if the flag was successfully set; otherwise, NO.
- (BOOL)trySet;

// Tries to clear the flag. Returns YES, if the flag was successfully cleared; otherwise, NO.
- (BOOL)tryClear;

@end
