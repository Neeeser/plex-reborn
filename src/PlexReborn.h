// Shared between Plex Reborn's source files.
#import <UIKit/UIKit.h>

// Settings (stored in the app's NSUserDefaults under "PlexReborn.*").
extern NSString *const PLXSettingCustomTabBar;      // BOOL, default NO
extern NSString *const PLXSettingTabBarItems;       // NSArray<NSString *> of tab IDs
extern NSString *const PLXSettingRowsUnderBar;      // BOOL, default YES
extern NSString *const PLXSettingFullWidthMiniPlayer; // BOOL, default YES
extern NSString *const PLXSettingBarButtonsInVerticalBar; // BOOL, default YES
extern NSString *const PLXSettingsDidChangeNotification;

BOOL PLXSettingBool(NSString *key);

// A tab the custom tab bar can show. IDs are "home:<title>" for the tabs of
// Plex's Home screen and "menu:<title>|<subtitle>" for side menu entries.
@interface PLXTabEntry : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, strong, nullable) UIImage *image;
@end

// Every tab currently available, from Plex's Home tab bar and side menu.
NSArray<PLXTabEntry *> *PLXAvailableTabEntries(void);
