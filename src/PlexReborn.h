// Shared between Plex Reborn's source files.
#import <UIKit/UIKit.h>

// Settings (stored in the app's NSUserDefaults under "PlexReborn.*").
extern NSString *const PLXSettingCustomTabBar;      // BOOL, default NO
extern NSString *const PLXSettingTabBarItems;       // NSArray<NSString *> of tab IDs
extern NSString *const PLXSettingRowsUnderBar;      // BOOL, default YES
extern NSString *const PLXSettingMiniPlayerStyle;   // PLXMiniPlayerStyle, default floating card
extern NSString *const PLXSettingBarButtonsInVerticalBar; // BOOL, default YES
extern NSString *const PLXSettingClearTitleBar;     // BOOL, default YES
extern NSString *const PLXSettingDeskReflection;    // BOOL, default YES
extern NSString *const PLXSettingGlassPlayerControls; // BOOL, default YES
extern NSString *const PLXSettingLibraryTabs;       // PLXLibraryTabsPlacement, default button
// Plex's online content, hidden per kind. Each defaults to version 0.1.0's single switch.
extern NSString *const PLXSettingHideMoviesAndShows; // BOOL
extern NSString *const PLXSettingHideRentals;        // BOOL
extern NSString *const PLXSettingHideDiscover;       // BOOL
extern NSString *const PLXSettingHidePlexLiveTV;     // BOOL
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

// Restyles the full-screen player's controls inside Plex's player view
// (PMVideoPlayerViewController's view); called after each layout of the video.
void PLXUpdatePlayerControls(UIView *player);
NSInteger PLXSettingInteger(NSString *key);

// The vertical bar button for the library tabs of the screen that owns this
// navigation item, or nil when that screen has none or another placement is chosen.
UIBarButtonItem *PLXLibraryTabsItemForNavigationItem(UINavigationItem *item);

// YES for the library tabs button Plex Reborn adds, which is never one of Plex's own buttons.
BOOL PLXIsLibraryTabsButton(UIBarButtonItem *item);

// The mini player is a floating card, so content and the vertical bar's tabs run past it.
BOOL PLXMiniPlayerFloats(UIView *miniPlayer);

// Plex's mini player: PMMiniPlayerView on compact-width screens (folded) and
// PMMiniPlayerViewFullSize on regular-width ones (unfolded landscape).
BOOL PLXIsMiniPlayerView(UIView *view);

// Width of the vertical bar's column (12 pt padding, 48 pt bar, 24 pt to the
// edge). The folded screen reserves it as a safe-area inset; the unfolded
// screen does not, so code that sits beside the bar uses at least this much.
static const CGFloat PLXVerticalBarColumnWidth = 84;

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
