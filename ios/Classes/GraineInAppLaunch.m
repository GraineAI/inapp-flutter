#import <UIKit/UIKit.h>

// GraineCallsHost, from this plugin's Swift (the Graine iOS SDK it carries).
#if __has_include(<graine_inapp/graine_inapp-Swift.h>)
#import <graine_inapp/graine_inapp-Swift.h>
#else
#import "graine_inapp-Swift.h"
#endif

/**
 * A VoIP push that wakes a terminated app must reach PushKit, and be reported
 * to CallKit, during launch: iOS stops delivering VoIP pushes to an app that
 * does not. An app delegate registers its plugins inside didFinishLaunching,
 * and GraineInAppPlugin restores the calls as it is registered. An app on the
 * scene lifecycle registers them when its Flutter engine starts, which waits
 * for a scene, and a push that wakes the app in the background may never bring
 * one. So the calls also restore themselves here, as the app finishes
 * launching; whichever comes first configures them, and the other finds them
 * configured. The observer runs on the posting thread (the main thread,
 * inside launch), not later on a queue.
 */
@interface GraineInAppLaunch : NSObject
@end

@implementation GraineInAppLaunch

static id<NSObject> graineLaunchObserver;

+ (void)load
{
  graineLaunchObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:UIApplicationDidFinishLaunchingNotification
                  object:nil
                   queue:nil
              usingBlock:^(__unused NSNotification *note) {
                [GraineCallsHost.shared restore];
                [[NSNotificationCenter defaultCenter] removeObserver:graineLaunchObserver];
                graineLaunchObserver = nil;
              }];
}

@end
