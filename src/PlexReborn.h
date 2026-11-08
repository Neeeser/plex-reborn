// Shared between Plex Reborn's source files.
#import <UIKit/UIKit.h>

// Settings (stored in the app's NSUserDefaults under "PlexReborn.*").
extern NSString *const PLXSettingCustomTabBar;      // BOOL, default NO
extern NSString *const PLXSettingTabBarItems;       // NSArray<NSString *> of tab IDs
extern NSString *const PLXSettingRowsUnderBar;      // BOOL, default YES
extern NSString *const PLXSettingMiniPlayerStyle;   // PLXMiniPlayerStyle, default floating card
extern NSString *const PLXSettingBarButtonsInVerticalBar; // BOOL, default YES
extern NSString *const PLXSettingClearTitleBar;     // BOOL, default YES
extern NSString *const PLXSettingLibraryTabs;       // PLXLibraryTabsPlacement, default button
extern NSString *const PLXSettingsDidChangeNotification;

// Where a library's own tabs (Recommended, Library, Categories) go while the
// vertical bar shows.
typedef NS_ENUM(NSInteger, PLXLibraryTabsPlacement) {
    PLXLibraryTabsButton = 0,      // one button in the vertical bar with a menu of the tabs
    PLXLibraryTabsVerticalBar = 1, // the tabs themselves in the vertical bar
    PLXLibraryTabsPlexBar = 2,     // Plex's own bar at the bottom
};

// How the mini player looks while the vertical bar shows.
typedef NS_ENUM(NSInteger, PLXMiniPlayerStyle) {
    PLXMiniPlayerFloatingCard = 0, // a glass card over the content beside the vertical bar's tabs
    PLXMiniPlayerFullWidth = 1,    // Plex's bar, with the row using the full width
    PLXMiniPlayerPlex = 2,         // Plex's bar as Plex lays it out
};

BOOL PLXSettingBool(NSString *key);
NSInteger PLXSettingInteger(NSString *key);

// The vertical bar button for the library tabs of the screen that owns this
// navigation item, or nil when that screen has none or another placement is chosen.
UIBarButtonItem *PLXLibraryTabsItemForNavigationItem(UINavigationItem *item);

// The mini player is a floating card, so content and the vertical bar's tabs run past it.
BOOL PLXMiniPlayerFloats(UIView *miniPlayer);

// Top of the tabs shown in the vertical bar, in window coordinates; CGFLOAT_MAX when none show.
CGFloat PLXVerticalTabsTop(UIWindow *window);

// A tab the custom tab bar can show. IDs are "home:<title>" for the tabs of
// Plex's Home screen and "menu:<title>|<subtitle>" for side menu entries.
@interface PLXTabEntry : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;    // nil when the entry has none
@property (nonatomic, strong) UIImage *image;
@end

// Every tab currently available, from Plex's Home tab bar and side menu.
NSArray<PLXTabEntry *> *PLXAvailableTabEntries(void);
