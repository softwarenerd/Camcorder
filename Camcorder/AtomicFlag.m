//
//  AtomicFlag.m
//
//  Created by Brian Lambert on 3/21/12.
//  Copyright (c) 2012 Brian Lambert. All rights reserved.
//

#import "AtomicFlag.h"
#import "libkern/OSAtomic.h"

// AtomicFlag implementation.
@implementation AtomicFlag
{
@private
    // The flag.
    volatile int32_t flag_;
}

// Returns YES, if the flag is clear; otherwise, NO.
- (BOOL)isClear
{
    return OSAtomicCompareAndSwap32Barrier(0, 0, &flag_);
}

// Returns YES, if the flag is set; otherwise, NO.
- (BOOL)isSet
{
    return OSAtomicCompareAndSwap32Barrier(1, 1, &flag_);
}

// Tries to set the flag. Returns YES, if the flag was successfully set; otherwise, NO.
- (BOOL)trySet
{
    return OSAtomicCompareAndSwap32Barrier(0, 1, &flag_);
}

// Tries to clear the flag. Returns YES, if the flag was successfully cleared; otherwise, NO.
- (BOOL)tryClear
{
    return OSAtomicCompareAndSwap32Barrier(1, 0, &flag_);
}

@end
