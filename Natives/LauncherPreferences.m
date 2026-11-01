#import "config.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "UIKit+hook.h"
#import <CoreFoundation/CoreFoundation.h>

static PLPreferences* pref;

void loadPreferences(BOOL reset) {
    assert(getenv("AME_HOME"));
    if (reset) {
        [pref reset];
    } else {
        pref = [[PLPreferences alloc] initWithAutomaticMigrator];
    }
}

void toggleIsolatedPref(BOOL forceEnable) {
    if (!pref.instancePath) {
        pref.instancePath = [NSString stringWithFormat:@"%s/launcher_preferences.plist", getenv("GAME_DIR")];
    }
    [pref toggleIsolationForced:forceEnable];
}

id getPrefObject(NSString *key) {
    return [pref getObject:key];
}
BOOL getPrefBool(NSString *key) {
    return [getPrefObject(key) boolValue];
}
float getPrefFloat(NSString *key) {
    return [getPrefObject(key) floatValue];
}
NSInteger getPrefInt(NSString *key) {
    return [getPrefObject(key) intValue];
}

void setPrefObject(NSString *key, id value) {
    [pref setObject:key value:value];
}
void setPrefBool(NSString *key, BOOL value) {
    setPrefObject(key, @(value));
}
void setPrefFloat(NSString *key, float value) {
    setPrefObject(key, @(value));
}
void setPrefInt(NSString *key, NSInteger value) {
    setPrefObject(key, @(value));
}

void resetWarnings() {
    for (int i = 0; i < pref.globalPref[@"warnings"].count; i++) {
        NSString *key = pref.globalPref[@"warnings"].allKeys[i];
        pref.globalPref[@"warnings"][key] = @YES;
    }
}

#pragma mark Safe area

CGRect getSafeArea(CGRect screenBounds) {
    UIEdgeInsets safeArea = UIEdgeInsetsFromString(getPrefObject(@"control.control_safe_area"));
    if (screenBounds.size.width < screenBounds.size.height) {
        safeArea = UIEdgeInsetsMake(safeArea.right, safeArea.top, safeArea.left, safeArea.bottom);
    }
    return UIEdgeInsetsInsetRect(screenBounds, safeArea);
}

void setSafeArea(CGSize screenSize, CGRect frame) {
    UIEdgeInsets safeArea;
    // TODO: make safe area consistent across opposite orientations?
    if (screenSize.width < screenSize.height) {
        safeArea = UIEdgeInsetsMake(
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame),
            frame.origin.y);
    } else {
        safeArea = UIEdgeInsetsMake(
            frame.origin.y,
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame));
    }
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(safeArea));
}

UIEdgeInsets getDefaultSafeArea() {
    UIEdgeInsets safeArea = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    if (screenSize.width < screenSize.height) {
        safeArea.left = safeArea.top;
        safeArea.right = safeArea.bottom;
    }
    safeArea.top = safeArea.bottom = 0;
    return safeArea;
}

#pragma mark Java runtime

// Saved preferences only get missing top-level keys filled in, so a runtime that was added to the app
// later (like Java 25) never showed up for users who already had preferences. Register every runtime
// that ships inside the app bundle.
static void registerBundledJavaRuntimes(void) {
    NSString *dir = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"java_runtimes"];
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
    NSMutableDictionary *homes = [getPrefObject(@"java.java_homes") mutableCopy];
    if (!homes) return;
    BOOL changed = NO;
    for (NSString *item in items) {
        // java-25-openjdk -> 25
        if (![item hasPrefix:@"java-"] || ![item hasSuffix:@"-openjdk"]) continue;
        NSString *version = [[item substringFromIndex:5] stringByReplacingOccurrencesOfString:@"-openjdk" withString:@""];
        if (version.intValue <= 0 || homes[version]) continue;
        NSLog(@"[JavaLauncher] Registering bundled Java %@", version);
        homes[version] = @"internal";
        changed = YES;
    }
    if (changed) {
        setPrefObject(@"java.java_homes", homes);
    }
}

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion) {
    registerBundledJavaRuntimes();
    NSDictionary *pref = getPrefObject(@"java.java_homes");
    NSDictionary<NSString *, NSString *> *selected = pref[@"0"];
    NSString *selectedVer = selected[defaultJRETag];
    if (minVersion > selectedVer.intValue) {
        // The selected runtime is too old. Look for the oldest installed one that is new enough.
        // (selectedVer must be cleared first, otherwise a failed search silently kept the old runtime
        // and the game crashed with UnsupportedClassVersionError instead of reporting a missing Java.)
        selectedVer = nil;
        NSArray *sortedVersions = [pref.allKeys valueForKeyPath:@"self.integerValue"];
        sortedVersions = [sortedVersions sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *version in sortedVersions) {
            if (version.intValue >= minVersion) {
                selectedVer = version.stringValue;
                break;
            }
        }
        if (!selectedVer) {
            NSLog(@"Error: requested Java >= %d was not installed!", minVersion);
            return nil;
        }
    }

    id selectedDir = pref[selectedVer];
    if ([selectedDir isEqualToString:@"internal"]) {
        selectedDir = [NSString stringWithFormat:@"%@/java_runtimes/java-%@-openjdk", NSBundle.mainBundle.bundlePath, selectedVer];
    } else {
        selectedDir = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("AME_HOME"), selectedDir];
    }

    if ([NSFileManager.defaultManager fileExistsAtPath:selectedDir]) {
        return selectedDir;
    } else {
        NSLog(@"Error: selected runtime for %@ does not exist: %@", defaultJRETag, selectedDir);
        return nil;
    }
}

#pragma mark Renderer
NSArray* getRendererKeys(BOOL containsDefault) {
    NSMutableArray *array = @[
        @"auto",
        @ RENDERER_NAME_GL4ES,
        @ RENDERER_NAME_MTL_ANGLE,
        @ RENDERER_NAME_MOBILEGLUES,
        @ RENDERER_NAME_VK_ZINK
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    
    return array;
}

NSArray* getRendererNames(BOOL containsDefault) {
    NSMutableArray *array;

    array = @[
        localize(@"preference.title.renderer.debug.auto", nil),
        localize(@"preference.title.renderer.debug.gl4es", nil),
        localize(@"preference.title.renderer.debug.angle", nil),
        localize(@"preference.title.renderer.debug.mg", nil),
        localize(@"preference.title.renderer.debug.zink", nil)
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }

    return array;
}
