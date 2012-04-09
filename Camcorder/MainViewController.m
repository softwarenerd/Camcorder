//
//  ViewController.m
//  Camcorder
//
//  Created by Brian Lambert on 4/6/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "MainViewController.h"
#import "Camcorder.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <AssetsLibrary/AssetsLibrary.h>

// MainViewController (VideoCameraDelegate) interface.
@interface MainViewController (CamcorderDelegate) <CamcorderDelegate>
@end

// MainViewController (Internal) interface.
@interface MainViewController (Internal)

// Update the status.
- (void)updateStatus;

// Called when the video camera is turned on.
- (void)videoCameraTurnedOn;

// Called when the video camera is turned off.
- (void)videoCameraTurnedOff;

// buttonOnOffTouchUpInside action.
- (void)buttonOnOffTouchUpInside:(UIButton *)sender;

// buttonRecordTouchUpInside action.
- (void)buttonRecordTouchUpInside:(UIButton *)sender;

// buttonFrontCameraTouchUpInside action.
- (void)buttonFrontCameraTouchUpInside:(UIButton *)sender;

// buttonBackCameraTouchUpInside action.
- (void)buttonBackCameraTouchUpInside:(UIButton *)sender;

@end

// MainViewController implementation.
@implementation MainViewController
{
@private
    // The camcorder.
    Camcorder * camcorder_;
    
    // The video preview view.
    UIView * videoPreviewView_;
    
    // The status label.
    UILabel * labelStatus_;
    
    // The video preview layer which is added to the video preview view.
    AVCaptureVideoPreviewLayer *  captureVideoPreviewLayer_;

    // The camera on/off button.
    UIButton * buttonOnOff_;

    // The camera record button.
    UIButton * buttonRecord_;

    // The front camera button.
    UIButton * buttonFrontCamera_;

    // The back camera button.
    UIButton * buttonBackCamera_;
}

// Called after the controller’s view is loaded into memory.
- (void)viewDidLoad
{
    // Call the base class's method.
    [super viewDidLoad];
        
    // Allocate and initialize the camcorder.
    NSURL * outputDirectoryURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    camcorder_ = [[Camcorder alloc] initWithOutputDirectoryURL:outputDirectoryURL
                                                         width:1920
                                                        height:1080
                                                  captureAudio:YES];
    [camcorder_ setDelegate:(id <CamcorderDelegate>)self];
    [camcorder_ start];
    [camcorder_ setCameraPosition:CameraPositionBack];
    
    // Allocate, initialize, and add the view preview view.
    videoPreviewView_ = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 180.0)];
    [videoPreviewView_ setBackgroundColor:[UIColor whiteColor]];
    [videoPreviewView_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin];
    [[self view] addSubview:videoPreviewView_];
    
    // Allocate and initialize the button font.
    UIFont * font = [UIFont fontWithName:@"Helvetica-Bold" size:12.0];
    CGFloat fontHeight = [font lineHeight];

    // Allocate, initialize, and add the status label.
    labelStatus_ = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 190.0, 300.0, fontHeight)];
    [labelStatus_ setFont:font];
    [labelStatus_ setTextAlignment:UITextAlignmentCenter];
    [labelStatus_ setBackgroundColor:[UIColor clearColor]];
    [labelStatus_ setTextColor:[UIColor whiteColor]];
    [labelStatus_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin];
    [[self view] addSubview:labelStatus_];
    
    // Obtain the capture video preview layer and insert it into the video preview view.
    captureVideoPreviewLayer_ = [camcorder_ captureVideoPreviewLayer];    
    [captureVideoPreviewLayer_ setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [captureVideoPreviewLayer_ setFrame:CGRectMake(0.0, 0.0, 320.0, 180.0)];
    [captureVideoPreviewLayer_ setHidden:YES];
    [[videoPreviewView_ layer] insertSublayer:captureVideoPreviewLayer_ atIndex:0];

    // Allocate, initialize, and add the on/off button.
    buttonOnOff_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [buttonOnOff_ setFrame:CGRectMake(10.0, 400.0, 145.0, 35.0)];
    [[buttonOnOff_ titleLabel] setFont:font];
    [buttonOnOff_ setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [buttonOnOff_ setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    [buttonOnOff_ setTitle:@"Camera On / Off" forState:UIControlStateNormal];
    [buttonOnOff_ addTarget:self action:@selector(buttonOnOffTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [buttonOnOff_ setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
    [[self view] addSubview:buttonOnOff_];
    
    // Allocate, initialize, and add the record button.
    buttonRecord_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [buttonRecord_ setFrame:CGRectMake(165.0, 400, 145.0, 35.0)];
    [[buttonRecord_ titleLabel] setFont:font];
    [buttonRecord_ setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [buttonRecord_ setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    [buttonRecord_ setTitle:@"Record" forState:UIControlStateNormal];
    [buttonRecord_ addTarget:self action:@selector(buttonRecordTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [buttonRecord_ setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
    [[self view] addSubview:buttonRecord_];

    // Allocate, initialize, and add the front camera button.
    buttonFrontCamera_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [buttonFrontCamera_ setFrame:CGRectMake(10.0, 445.0, 145.0, 35.0)];
    [[buttonFrontCamera_ titleLabel] setFont:font];
    [buttonFrontCamera_ setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [buttonFrontCamera_ setTitle:@"Front Position" forState:UIControlStateNormal];
    [buttonFrontCamera_ addTarget:self action:@selector(buttonFrontCameraTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [buttonFrontCamera_ setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
    [[self view] addSubview:buttonFrontCamera_];

    // Allocate, initialize, and add the back camera button.
    buttonBackCamera_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [buttonBackCamera_ setFrame:CGRectMake(165.0, 445.0, 145.0, 35.0)];
    [[buttonBackCamera_ titleLabel] setFont:font];
    [buttonBackCamera_ setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [buttonBackCamera_ setTitle:@"Back Position" forState:UIControlStateNormal];
    [buttonBackCamera_ addTarget:self action:@selector(buttonBackCameraTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [buttonBackCamera_ setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
    [[self view] addSubview:buttonBackCamera_];

    // Update the status.
    [self updateStatus];
}

// Called when the controller’s view is released from memory.
- (void)viewDidUnload
{
    [super viewDidUnload];
}

// Returns a Boolean value indicating whether the view controller supports the specified orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    // Adjust for orientation.
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation))
    {
        [captureVideoPreviewLayer_ setOrientation:AVCaptureVideoOrientationPortrait];
    }
    else if (interfaceOrientation == UIInterfaceOrientationLandscapeLeft)
    {
        [captureVideoPreviewLayer_ setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    }
    else if (interfaceOrientation == UIInterfaceOrientationLandscapeRight)
    {
        [captureVideoPreviewLayer_ setOrientation:AVCaptureVideoOrientationLandscapeRight];
    }
}

@end

// MainViewController (CamcorderDelegate) implementation.
@implementation MainViewController (CamcorderDelegate)

// Notifies the delegate that the camcorder did turn on.
- (void)camcorderDidTurnOn:(Camcorder *)camcorder
{
    [self videoCameraTurnedOn];    
}

// Notifies the delegate that the camcorder did turn off.
- (void)camcorderDidTurnOff:(Camcorder *)camcorder
{
    [self videoCameraTurnedOff];    
}

// Notifies the delegate that the camcorder did start recording.
- (void)camcorderDidStartRecording:(Camcorder *)camcorder
{
}

// Notifies the delegate that the camcorder did finish recording.
- (void)camcorderFinishedRecording:(Camcorder *)camcorder videoFilePath:(NSString *)videoFilePath
{
}

// Notifies the delegate of the recording elapsed time interval.
- (void)camcorder:(Camcorder *)camcorder recordingElapsedTimeInterval:(NSTimeInterval)recordingElapsedTimeInterval
{
}

// Notifies the delegate that the camcorder device configuration changed.
- (void)camcorderDeviceConfigurationChanged:(Camcorder *)camcorder
{    
}

// Notifies the delegate that the camcorder failed with an error.
- (void)camcorder:(Camcorder *)camcorder didFailWithError:(NSError *)error
{
    NSLog(@"Camcorder error %i", [error code]);
}

@end

// MainViewController (Internal) implementation.
@implementation MainViewController (Internal)

// Update the status.
- (void)updateStatus
{
    //[labelStatus_ setText:[NSString stringWithFormat:@"%@ is %@", cameraPosition, [camcorder_ isOn] ? @"ON" : @"OFF"]];
}

// Called when the video camera is turned on.
- (void)videoCameraTurnedOn
{
    // If this is not the main thread, perform this selector on the main thread and return.
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(videoCameraTurnedOn) withObject:nil waitUntilDone:NO];
        return;
    }

    [captureVideoPreviewLayer_ setHidden:NO];
    [buttonOnOff_ setEnabled:YES];
    [self updateStatus];
}

// Called when the video camera is turned off.
- (void)videoCameraTurnedOff
{
    // If this is not the main thread, perform this selector on the main thread and return.
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(videoCameraTurnedOff) withObject:nil waitUntilDone:NO];
        return;
    }

    [captureVideoPreviewLayer_ setHidden:YES];
    [buttonOnOff_ setEnabled:YES];
    [self updateStatus];
}

// buttonOnOffTouchUpInside action.
- (void)buttonOnOffTouchUpInside:(UIButton *)sender
{        
    if (![camcorder_ isOn])
    {
        [camcorder_ turnOn];
    }
    else
    {
        [camcorder_ turnOff];
    }
    
    [buttonOnOff_ setEnabled:NO];
}

// buttonFrontCameraTouchUpInside action.
- (void)buttonFrontCameraTouchUpInside:(UIButton *)sender
{
    [camcorder_ setCameraPosition:CameraPositionFront];
    
    [self updateStatus];
}

// buttonBackCameraTouchUpInside action.
- (void)buttonBackCameraTouchUpInside:(UIButton *)sender
{
    [camcorder_ setCameraPosition:CameraPositionBack];
    
    [self updateStatus];
}


// buttonRecordTouchUpInside action.
- (void)buttonRecordTouchUpInside:(UIButton *)sender
{
    if (![camcorder_ isRecording])
    {
        [camcorder_ startRecording];
    }
    else
    {
        [camcorder_ stopRecording];
    }

    [self updateStatus];
}

@end

