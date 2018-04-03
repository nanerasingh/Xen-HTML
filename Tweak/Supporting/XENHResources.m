/*
 Copyright (C) 2018  Matt Clarke
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License along
 with this program; if not, write to the Free Software Foundation, Inc.,
 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#import "XENHResources.h"
#import "XENHWebViewController.h"
#import <objc/runtime.h>

@interface XENResources : NSObject
+(BOOL)enabled;
+(BOOL)useGroupedNotifications;
+(NSString*)currentlyShownNotificationAppIdentifier;
@end

@interface PHContainerView : UIView
+(id)_xenhtml_sharedPH;
@property (readonly) NSString* selectedAppID;
@end

@interface SBLockScreenNotificationListController : NSObject
- (unsigned long long)count;
@end

@interface SBDashBoardNotificationListViewController : NSObject
@property(readonly, nonatomic) _Bool hasContent;
@end

@interface SBDashBoardMainPageContentViewController : UIViewController
@property(readonly, nonatomic) SBDashBoardNotificationListViewController *notificationListViewController;
@end

@interface SBDashBoardMainPageViewController : UIViewController
@property(readonly, nonatomic) SBDashBoardMainPageContentViewController *contentViewController;
@end

@interface SBDashBoardViewController : UIViewController
@property(retain, nonatomic) SBDashBoardMainPageViewController *mainPageViewController;
@end

@interface SBLockScreenManager : NSObject
+(instancetype)sharedInstance;
- (id)lockScreenViewController;
@end

static NSDictionary *settings;
static NSBundle *strings;
static int currentOrientation = 1;
static BOOL phIsVisible;
static BOOL xenIsVisible;
static NSUserDefaults *PHDefaults;
static SBLockScreenNotificationListController * __weak cachedLSNotificationController;
static int iOS10NotificationCount;

@implementation XENHResources

void XenHTMLLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...) {
    // Type to hold information about variable arguments.
    
    if (![XENHResources debugLogging]) {
        return;
    }
    
    va_list ap;
    
    // Initialize a variable argument list.
    va_start (ap, format);
    
    // NSLog only adds a newline to the end of the NSLog format if
    // one is not already there.
    // Here we are utilizing this feature of NSLog()
    if (![format hasSuffix: @"\n"]) {
        format = [format stringByAppendingString: @"\n"];
    }
    
    NSString *body = [[NSString alloc] initWithFormat:format arguments:ap];
    
    // End using variable argument list.
    va_end(ap);
    
    NSString *fileName = [[NSString stringWithUTF8String:file] lastPathComponent];
    
    NSLog(@"Xen HTML :: (%s:%d) %s",
          [fileName UTF8String],
          lineNumber, [body UTF8String]);
    //NSString *stringToLog = [NSString stringWithFormat:@"Xen HTML :: (%s:%d) %s", [fileName UTF8String], lineNumber, [body UTF8String]];
    //os_log(OS_LOG_DEFAULT, [stringToLog UTF8String]);
    
    // Append to log file
    /*NSString *txtFileName = @"/var/mobile/Documents/XenDebug.txt";
     NSString *final = [NSString stringWithFormat:@"(%s:%d) %s", [fileName UTF8String],
     lineNumber, [body UTF8String]];
     
     NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:txtFileName];
     if (fileHandle) {
     [fileHandle seekToEndOfFile];
     [fileHandle writeData:[final dataUsingEncoding:NSUTF8StringEncoding]];
     [fileHandle closeFile];
     } else{
     [final writeToFile:txtFileName
     atomically:NO
     encoding:NSStringEncodingConversionAllowLossy
     error:nil];
     }*/
}

+(BOOL)debugLogging {
    return YES;
}

+(NSString*)localisedStringForKey:(NSString*)key value:(NSString*)val {
    if (!strings) {
        strings = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/XenHTMLPrefs.bundle"];
    }
    
    if (!strings) {
        // wtf CoolStar
        return val;
    }
    
    return [strings localizedStringForKey:key value:val table:nil];
}

+(CGRect)boundedRectForFont:(UIFont*)font andText:(NSString*)text width:(CGFloat)width {
    if (!text || !font) {
        return CGRectZero;
    }
    
    if (![text isKindOfClass:[NSAttributedString class]]) {
        NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName:font}];
        CGRect rect = [attributedText boundingRectWithSize:(CGSize){width, CGFLOAT_MAX}
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                   context:nil];
        return rect;
    } else {
        return [(NSAttributedString*)text boundingRectWithSize:(CGSize){width, CGFLOAT_MAX}
                                                       options:NSStringDrawingUsesLineFragmentOrigin
                                                       context:nil];
    }
}

+(CGSize)getSizeForText:(NSString *)text maxWidth:(CGFloat)width font:(NSString *)fontName fontSize:(float)fontSize {
    CGSize constraintSize;
    constraintSize.height = MAXFLOAT;
    constraintSize.width = width;
    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [UIFont fontWithName:fontName size:fontSize], NSFontAttributeName,
                                          nil];
    
    CGRect frame = [text boundingRectWithSize:constraintSize
                                      options:NSStringDrawingUsesLineFragmentOrigin
                                   attributes:attributesDictionary
                                      context:nil];
    
    CGSize stringSize = frame.size;
    return stringSize;
}

+(NSString*)imageSuffix {
    NSString *suffix = @"";
    switch ((int)[UIScreen mainScreen].scale) {
        case 2:
            suffix = @"@2x";
            break;
        case 3:
            suffix = @"@3x";
            break;
            
        default:
            break;
    }
    
    return [NSString stringWithFormat:@"%@.png", suffix];
}

#pragma mark Load up HTML

+(UIView*)widgetsView {
    return nil;
}

+(XENHWebViewController*)configuredHTMLViewControllerForLocation:(XENHViewLocation)location {
    if (location == kLocationWidgets) {
        return nil;
    }
    
    NSString *baseString = [XENHResources indexHTMLFileForLocation:location];
    
    XENHWebViewController *controller = [[XENHWebViewController alloc] initWithBaseString:baseString];
    controller.variant = location;
    
    return controller;
}

+(BOOL)_recursivelyCheckForGroovyAPI:(NSString*)folder {
    NSError *error;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:&error];
    
    BOOL output = NO;
    
    for (NSString *item in contents) {
        NSString *fullpath = [NSString stringWithFormat:@"%@/%@", folder, item];
        
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:fullpath isDirectory:&isDir];
        
        if (isDir) {
            output = [self _recursivelyCheckForGroovyAPI:fullpath];
            
            if (output)
                break;
        } else {
            // Check for groovyAPI if suffix is .js
            
            if ([item hasSuffix:@".js"]) {
                XENlog(@"Checking %@ for groovyAPI", item);
                
                NSError *error;
                
                NSString *string = [NSString stringWithContentsOfFile:fullpath encoding:NSUTF8StringEncoding error:&error];
                
                if (!error && [string rangeOfString:@"groovyAPI."].location != NSNotFound) {
                    output = YES;
                    break;
                }
            }
        }
    }
    
    return output;
}

+(BOOL)useFallbackForHTMLFile:(NSString*)filePath {
    // First, check if override applies.
    BOOL isSB = [filePath isEqualToString:[self indexHTMLFileForLocation:kLocationSBHTML]];
    BOOL forceLegacy = (isSB ? [self SBUseLegacyMode] : [self LSUseLegacyMode]);
    
    if (forceLegacy) {
        return YES;
    }
    
    BOOL value = NO;
    NSError *error;
    
    NSString *string = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    
    if (!error && [string rangeOfString:@"text/cycript"].location != NSNotFound) {
        value = YES;
    }
    
    // Handle groovyAPI.

    // We will also iterate recursively through this widget, and check if it needs groovyAPI.
    // Docs: https://web.archive.org/web/20150910231544/http://www.groovycarrot.co.uk/groovyapi/
    // First, we will check the incoming .html.
        
    BOOL hasgAPI = NO;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/groovyAPI.dylib" isDirectory:NO]) {
        if (!error && [string rangeOfString:@"groovyAPI."].location != NSNotFound) {
            hasgAPI = YES;
        } else {
            NSString *topHeirarchy = [filePath stringByDeletingLastPathComponent];
            
            hasgAPI = [self _recursivelyCheckForGroovyAPI:topHeirarchy];
            XENlog(@"Has groovyAPI: %d", hasgAPI);
        }
    }
    
    if (hasgAPI)
        value = YES;
    
    return value;
}

+(NSDictionary*)rawMetadataForHTMLFile:(NSString*)filePath {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    // First, check if this is an iWidget.
    // If so, we can fill in the size from Widget.plist
    // Also, we can fill in default values from Options.plist if available, and then re-populate with user set values.
    NSString *path = [filePath stringByDeletingLastPathComponent];
    NSString *lastPathComponent = [filePath lastPathComponent];
    
    NSString *widgetPlistPath = [path stringByAppendingString:@"/Widget.plist"];
    NSString *widgetInfoPlistPath = [path stringByAppendingString:@"/WidgetInfo.plist"];
    NSString *optionsPath = [path stringByAppendingString:@"/Options.plist"];
    
    // Only check Widget.plist if we're loading an iWidget
    if ([lastPathComponent isEqualToString:@"Widget.html"] && [[NSFileManager defaultManager] fileExistsAtPath:widgetPlistPath]) {
        [dict setValue:@NO forKey:@"isFullscreen"];
        
        NSDictionary *widgetPlist = [NSDictionary dictionaryWithContentsOfFile:widgetPlistPath];
        NSDictionary *size = [widgetPlist objectForKey:@"size"];
        
        if (size) {
            [dict setValue:[size objectForKey:@"width"] forKey:@"width"];
            [dict setValue:[size objectForKey:@"height"] forKey:@"height"];
        } else {
            [dict setValue:[NSNumber numberWithFloat:SCREEN_WIDTH] forKey:@"width"];
            [dict setValue:[NSNumber numberWithFloat:SCREEN_HEIGHT] forKey:@"height"];
        }
        
        // Ignore the initial position of the widget, as it's fundamentally not compatible with
        // how we do positioning. Plus, I'm lazy and it's close to release day.
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"x"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"y"];
        
    } else if ([[NSFileManager defaultManager] fileExistsAtPath:widgetInfoPlistPath]) {
        // Handle WidgetInfo.plist
        // This can be loaded for ANY HTML widget, which is neat.
        
        
        NSDictionary *widgetPlist = [NSDictionary dictionaryWithContentsOfFile:widgetInfoPlistPath];
        NSDictionary *size = [widgetPlist objectForKey:@"size"];
        id isFullscreenVal = [widgetPlist objectForKey:@"isFullscreen"];
        
        // Fullscreen.
        BOOL isFullscreen = (isFullscreenVal ? [isFullscreenVal boolValue] : YES);
        [dict setValue:[NSNumber numberWithBool:isFullscreen] forKey:@"isFullscreen"];
        
        if (size && !isFullscreen) {
            [dict setValue:[size objectForKey:@"width"] forKey:@"width"];
            [dict setValue:[size objectForKey:@"height"] forKey:@"height"];
        } else {
            [dict setValue:[NSNumber numberWithFloat:SCREEN_WIDTH] forKey:@"width"];
            [dict setValue:[NSNumber numberWithFloat:SCREEN_HEIGHT] forKey:@"height"];
        }
        
        // Default widget position
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"x"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"y"];
    } else {
        [dict setValue:@YES forKey:@"isFullscreen"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"x"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"y"];
        [dict setValue:[NSNumber numberWithFloat:SCREEN_WIDTH] forKey:@"width"];
        [dict setValue:[NSNumber numberWithFloat:SCREEN_HEIGHT] forKey:@"height"];
    }
    
    // Next, we handle default options.
    // If Widget.html is being loaded, or WidgetInfo.plist exists, load up the Options.plist and add into metadata.
    
    if (([lastPathComponent isEqualToString:@"Widget.html"] || [[NSFileManager defaultManager] fileExistsAtPath:widgetInfoPlistPath]) && [[NSFileManager defaultManager] fileExistsAtPath:optionsPath]) {
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        
        
        NSArray *optionsPlist = [NSArray arrayWithContentsOfFile:optionsPath];
        
        for (NSDictionary *option in optionsPlist) {
            NSString *name = [option objectForKey:@"name"];
            
            /* Options.plist will contain the following types:
             edit
             select
             switch
             */
            
            id value = nil;
            
            NSString *type = [option objectForKey:@"type"];
            if ([type isEqualToString:@"select"]) {
                NSString *defaultKey = [option objectForKey:@"default"];
                
                value = [[option objectForKey:@"options"] objectForKey:defaultKey];
            } else if ([type isEqualToString:@"switch"]) {
                value = [option objectForKey:@"default"];
            } else {
                value = [option objectForKey:@"default"];
            }
            
            [options setValue:value forKey:name];
        }
        
        [dict setValue:options forKey:@"options"];
    } else {
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        [dict setValue:options forKey:@"options"];
    }
    
    return dict;
}

+(NSDictionary*)_widgetMetadataForKey:(NSString*)key {
    /*
     * Keys:
     height
     width
     isFullscreen
     x (in % of screensize)
     y (in % of screensize)
     options : dict of jsVar->value
     hasConfigJs
     */
    
    /* Options.plist will contain the following types:
     edit
     select
     switch
     */
    
    NSDictionary *dict = [settings objectForKey:@"widgetPrefs"];
    dict = [dict objectForKey:key];
    
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        
        [dict setValue:@YES forKey:@"isFullscreen"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"x"];
        [dict setValue:[NSNumber numberWithFloat:0.0] forKey:@"y"];
        [dict setValue:[NSNumber numberWithFloat:SCREEN_WIDTH] forKey:@"width"];
        [dict setValue:[NSNumber numberWithFloat:SCREEN_HEIGHT] forKey:@"height"];
        
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        [dict setValue:options forKey:@"options"];
    }
    
    return dict;
}

+(NSDictionary*)widgetMetadataForLocation:(int)location {
    NSString *key = @"";
    
    // First, work out which location this filePath corresponds to.
    if (location == kLocationBackground) {
        key = @"LSBackground";
    } else if (location == kLocationForeground) {
        key = @"LSForeground";
    } else if (location == kLocationSBHTML) {
        key = @"SBBackground";
    }
    
    return [self _widgetMetadataForKey:key];
}

+(NSDictionary*)widgetMetadataForHTMLFile:(NSString*)filePath {
    NSString *key = @"";
    
    // TODO: Well, cock. This forgets to account for the user maybe using the same widget on different layers.
    
    // First, work out which location this filePath corresponds to.
    if ([filePath isEqualToString:[self indexHTMLFileForLocation:kLocationBackground]]) {
        key = @"LSBackground";
    } else if ([filePath isEqualToString:[self indexHTMLFileForLocation:kLocationForeground]]) {
        key = @"LSForeground";
    } else if ([filePath isEqualToString:[self indexHTMLFileForLocation:kLocationSBHTML]]) {
        key = @"SBBackground";
    }
    
    return [self _widgetMetadataForKey:key];
}

+(void)setPreferenceKey:(NSString*)key withValue:(id)value andPost:(BOOL)post {
    if (!key || !value) {
        NSLog(@"Not setting value, as one of the arguments is null");
        return;
    }
    
    CFPreferencesAppSynchronize(CFSTR("com.matchstic.xenhtml"));
    NSMutableDictionary *settings = [(__bridge NSDictionary *)CFPreferencesCopyMultiple(CFPreferencesCopyKeyList(CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost), CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) mutableCopy];
    
    [settings setObject:value forKey:key];
    
    // Write to CFPreferences
    CFPreferencesSetValue ((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    
    [settings writeToFile:@"/var/mobile/Library/Preferences/com.matchstic.xenhtml.plist" atomically:YES];
    
    if (post) {
        // Notify that we've changed!
        CFStringRef toPost = (__bridge CFStringRef)@"com.matchstic.xenhtml/settingschanged";
        if (toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
    }
}

+(id)getPreferenceKey:(NSString*)key {
    return [settings objectForKey:key];
}

#pragma mark Settings handling

+(void)reloadSettings {
    CFPreferencesAppSynchronize(CFSTR("com.matchstic.xenhtml"));
    settings = (__bridge NSDictionary *)CFPreferencesCopyMultiple(CFPreferencesCopyKeyList(CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost), CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    
    // Convert iOS 10 clock hiding if needed.
    id value = settings[@"hideClockTransferred10"];
    BOOL hideTransferred = (value ? [value boolValue] : NO);
    
    if ([UIDevice currentDevice].systemVersion.floatValue >= 10 && !hideTransferred) {
        BOOL hideClock = [self hideClock];
        
        [self setPreferenceKey:@"hideClock10" withValue:[NSNumber numberWithInt:hideClock ? 2 : 0] andPost:YES];
        [self setPreferenceKey:@"hideClockTransferred10" withValue:[NSNumber numberWithBool:YES] andPost:YES];
        
        CFPreferencesAppSynchronize(CFSTR("com.matchstic.xenhtml"));
        settings = (__bridge NSDictionary *)CFPreferencesCopyMultiple(CFPreferencesCopyKeyList(CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost), CFSTR("com.matchstic.xenhtml"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
}

+(BOOL)lsenabled {
    // First, check whatever is set is valid for either background or foreground.
    /*BOOL exists = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self indexHTMLFileForLocation:kLocationBackground] isDirectory:NO]) {
        exists = YES;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self indexHTMLFileForLocation:kLocationForeground] isDirectory:NO]) {
        exists = YES;
    }
    
    if (!exists) {
        return NO;
    }*/
    
    id value = settings[@"enabled"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)xenInstalledAndGroupingIsMinimised {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/Xen.dylib"]) {
        if ([objc_getClass("XENResources") enabled] && [objc_getClass("XENResources") useGroupedNotifications]) {
            // Check if currently minimised or not
            /*if ([[objc_getClass("XENResources") currentlyShownNotificationAppIdentifier] isEqualToString:@""] || ![objc_getClass("XENResources") currentlyShownNotificationAppIdentifier]) {
                return YES;
            }*/
            return xenIsVisible;
        }
    }
    
    return NO;
}

+(BOOL)hideClock {
    id value = settings[@"hideClock"];
    return (value ? [value boolValue] : NO);
}

+(int)_hideClock10 {
    id value = settings[@"hideClock10"];
    return value ? [value intValue] : 0;
}

+(BOOL)hideSTU {
    id value = settings[@"hideSTU"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)useSameSizedStatusBar {
    id value = settings[@"sameSizedStatusBar"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)hideStatusBar {
    id value = settings[@"hideStatusBar"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)hidePageControlDots {
    id value = settings[@"hidePageControlDots"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)hideTopGrabber {
    if ([self LSShowClockInStatusBar]) {
        return YES;
    }
    
    id value = settings[@"hideTopGrabber"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)hideBottomGrabber {
    id value = settings[@"hideBottomGrabber"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)hideCameraGrabber {
    id value = settings[@"hideCameraGrabber"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)disableCameraGrabber {
    id value = settings[@"disableCameraGrabber"];
    return (value ? [value boolValue] : NO);
}

+(double)lockScreenIdleTime {    
    id temp = settings[@"lockScreenIdleTime"];
    return (temp ? [temp doubleValue] : 10.0);
}

+(BOOL)LSUseLegacyMode {
    id value = settings[@"LSUseLegacyMode"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSFadeForegroundForMedia {
    id value = settings[@"LSFadeForegroundForMedia"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)LSFadeForegroundForArtwork {
    if ([UIDevice currentDevice].systemVersion.floatValue >= 10) {
        return NO;
    }
    
    id value = settings[@"LSFadeForegroundForArtwork"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)LSHideArtwork {
    id value = settings[@"LSHideArtwork"];
    return (value ? [value boolValue] : NO);
}

//////////////////////////////////////////////////////
// iPhone X only
//////////////////////////////////////////////////////

+(BOOL)LSHideTorchAndCamera {
    id value = settings[@"LSHideTorchAndCamera"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSHideHomeBar {
    id value = settings[@"LSHideHomeBar"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSHideFaceIDPadlock {
    id value = settings[@"LSHideFaceIDPadlock"];
    return (value ? [value boolValue] : NO);
}

//////////////////////////////////////////////////////

+(BOOL)LSUseBatteryManagement {
    id value = settings[@"LSUseBatteryManagement"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)LSFadeForegroundForNotifications {
    id value = settings[@"LSFadeForegroundForNotifications"];
    return (value ? [value boolValue] : YES);
}

+(void)cacheNotificationListController:(id)controller {
    cachedLSNotificationController = controller;
}

+(void)cachePriorityHubVisibility:(BOOL)visible {
    phIsVisible = visible;
}

+(void)cacheXenGroupingVisibility:(BOOL)visible {
    xenIsVisible = visible;
}

+(void)addNewiOS10Notification {
    iOS10NotificationCount++;
}

+(void)removeiOS10Notification {
    iOS10NotificationCount--;
}

+(void)setiOS10NotiicationVisible:(BOOL)visible {
    iOS10NotificationCount = visible;
}

+(BOOL)isPriorityHubInstalledAndEnabled {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/PriorityHub.dylib"]) {
        if (!PHDefaults) {
            PHDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.thomasfinch.priorityhub"];
        }
        
        return [PHDefaults boolForKey:@"enabled"];
    } else {
        return NO;
    }
}

+(BOOL)isCallbarInstalledAndEnabled {
    return NO;
}

+(BOOL)LSInStateNotificationsHidden {
    // if the notification list view is of count 0, OR xenInstalledAndGroupingIsMinimised, then it's hidden.
    if (!phIsVisible && [self isPriorityHubInstalledAndEnabled]) {
        return YES;
    } else if ([self xenInstalledAndGroupingIsMinimised]) { // Xen second since PH takes priority in that tweak.
        return YES;
    }
    
    if ([UIDevice currentDevice].systemVersion.floatValue < 10.0) {
        if ([cachedLSNotificationController count] > 0) {
            return NO;
        }
    } else {
        SBDashBoardViewController *cont = [[objc_getClass("SBLockScreenManager") sharedInstance] lockScreenViewController];
        if (![cont isKindOfClass:objc_getClass("SBDashBoardViewController")]) {
            if ([cachedLSNotificationController count] > 0) {
                return NO;
            }
        } else {
            SBDashBoardMainPageContentViewController *content = cont.mainPageViewController.contentViewController;
        
            SBDashBoardNotificationListViewController *notif = content.notificationListViewController;
        
            return !notif.hasContent;
        }
    }
    
    return YES;
}

+(CGFloat)LSWidgetFadeOpacity {
    id value = settings[@"LSWidgetFadeOpacity"];
    return (value ? [value floatValue] : 0.5);
}

+(BOOL)LSFullscreenNotifications {
    id value = settings[@"LSFullscreenNotifications"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSShowClockInStatusBar {
    id value = settings[@"LSShowClockInStatusBar"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSBGAllowTouch {
    id value = settings[@"LSBGAllowTouch"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)LSWidgetScrollPriority {
    id value = settings[@"LSWidgetScrollPriority"];
    return (value ? [value boolValue] : NO);
}

#pragma mark SB

+(BOOL)SBEnabled {
    id value = settings[@"SBEnabled"];
    return (value ? [value boolValue] : YES);
}

+(BOOL)hideBlurredDockBG {
    id value = settings[@"SBHideDockBlur"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)hideBlurredFolderBG {
    id value = settings[@"SBHideFolderBlur"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)SBHideIconLabels {
    id value = settings[@"SBHideIconLabels"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)SBHidePageDots {
    id value = settings[@"SBHidePageDots"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)SBUseLegacyMode {
    id value = settings[@"SBUseLegacyMode"];
    return (value ? [value boolValue] : NO);
}

+(BOOL)SBAllowTouch {
    id value = settings[@"SBAllowTouch"];
    return (value ? [value boolValue] : YES);
}

/**
 * Gives the base URL of the chosen HTML file, whether it is index.html or whatever
 * @return Base URL path
 */
+(NSString*)indexHTMLFileForLocation:(XENHViewLocation)location {
    NSString *fileString = @"";
    
    if (location == kLocationBackground) {
        id value = settings[@"backgroundLocation"];
        fileString = (value ? value : @"");
    } else if (location == kLocationForeground) {
        id value = settings[@"foregroundLocation"];
        fileString = (value ? value : @"");
    } else if (location == kLocationSBHTML) {
        id value = settings[@"SBLocation"];
        fileString = (value ? value : @"");
    }
    
    return fileString;
}

/**
 * @return { <br>{ location: filename, x: 100, y: 100 },<br> { location: filename, x: 150, y: 150 }<br> }
 */
+(NSArray*)widgetLocations {
    id value = settings[@"widgetLocations"];
    return (value ? value : @{});
}

// Extra
+(void)setCurrentOrientation:(int)orient {
    currentOrientation = orient;
}

+(int)getCurrentOrientation {
    return currentOrientation;
}

+(BOOL)hasDisplayedSetupUI {
    id value = settings[@"hasDisplayedSetupUI"];
    return (value ? [value boolValue] : NO);
}

@end