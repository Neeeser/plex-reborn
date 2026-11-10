// Poster rows scroll behind the Duo's vertical bar.
//
// Plex's hub screens (Home, Trending, libraries) are table views whose cells
// each hold a horizontally scrolling row of posters. Table cells inset their
// content to the safe area, so with the Duo's vertical bar showing every row
// stops 84 pt short of the screen edge and the bar's strip is an empty column.
// Apple's Duo guidance is to let scrolling content and backgrounds run under
// the bar. For tables that hold horizontal rows, the cells now span the full
// width, and each row adds the bar's overlap to its content inset
// (contentInsetAdjustmentBehavior = always) so its last poster can still
// scroll clear of the bar. Tables of plain rows (settings, lists of text) are
// left alone so their text and controls stay inside the safe area.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static BOOL PLXIsHorizontalRow(UIView *view) {
    if (![view isKindOfClass:UICollectionView.class]) return NO;
    UICollectionViewLayout *layout = ((UICollectionView *)view).collectionViewLayout;
    if ([layout isKindOfClass:UICollectionViewFlowLayout.class]) {
        return ((UICollectionViewFlowLayout *)layout).scrollDirection == UICollectionViewScrollDirectionHorizontal;
    }
    if ([layout isKindOfClass:UICollectionViewCompositionalLayout.class]) {
        return ((UICollectionViewCompositionalLayout *)layout).configuration.scrollDirection == UICollectionViewScrollDirectionHorizontal;
    }
    // Plex's hub rows use their own layout class: judge by shape instead. A row
    // is wider in content than its frame, or no taller than its frame.
    CGSize content = ((UICollectionView *)view).contentSize;
    CGSize size = view.bounds.size;
    return content.width > size.width + 1 || (content.height > 0 && content.height <= size.height + 1);
}

// Horizontal rows within the first few levels of a cell's content view.
static void PLXCollectRows(UIView *view, NSUInteger depth, NSMutableArray<UICollectionView *> *rows) {
    if (PLXIsHorizontalRow(view)) { [rows addObject:(UICollectionView *)view]; return; }
    if (depth == 0) return;
    for (UIView *sub in view.subviews) PLXCollectRows(sub, depth - 1, rows);
}

static const void *PLXOriginalAdjustmentKey = &PLXOriginalAdjustmentKey;
static IMP PLXOrigTableLayout;

static void PLXTableLayoutSubviews(UITableView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTableLayout)(self, _cmd);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = self.window ? self.window.traitCollection.verticalBarEdge : 0;
    if (edge == 0) return;
    NSMutableArray<UICollectionView *> *rows = [NSMutableArray array];
    for (UITableViewCell *cell in self.visibleCells) PLXCollectRows(cell.contentView, 3, rows);
    if (rows.count == 0) return;
    BOOL under = PLXSettingBool(PLXSettingRowsUnderBar);
    if (self.insetsContentViewsToSafeArea == under) self.insetsContentViewsToSafeArea = !under;
    for (UICollectionView *row in rows) {
        // Remember Plex's own behavior so turning the setting off restores it.
        NSNumber *original = objc_getAssociatedObject(row, PLXOriginalAdjustmentKey);
        if (!original) {
            original = @(row.contentInsetAdjustmentBehavior);
            objc_setAssociatedObject(row, PLXOriginalAdjustmentKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIScrollViewContentInsetAdjustmentBehavior wanted = under ? UIScrollViewContentInsetAdjustmentAlways : original.integerValue;
        if (row.contentInsetAdjustmentBehavior != wanted) row.contentInsetAdjustmentBehavior = wanted;
    }
}

// Scroll bars are hidden on phones with the Duo's vertical bar. There they
// landed in odd places (left of the bar's column, or mid-screen while Plex's
// side menu slid the screen sideways). Other iPhones keep them. A scroll view
// hides them when it reaches such a window, and Plex's own attempts to turn
// them back on are ignored there.
static IMP PLXOrigSetShowsVertical, PLXOrigSetShowsHorizontal, PLXOrigScrollMoveToWindow;

static BOOL PLXHidesScrollBars(UIScrollView *scrollView) {
    if (@available(iOS 27.1, *)) return scrollView.window && scrollView.window.traitCollection.verticalBarEdge != 0;
    return NO;
}

static void PLXSetShowsVertical(UIScrollView *self, SEL _cmd, BOOL shows) {
    ((void (*)(id, SEL, BOOL))PLXOrigSetShowsVertical)(self, _cmd, shows && !PLXHidesScrollBars(self));
}

static void PLXSetShowsHorizontal(UIScrollView *self, SEL _cmd, BOOL shows) {
    ((void (*)(id, SEL, BOOL))PLXOrigSetShowsHorizontal)(self, _cmd, shows && !PLXHidesScrollBars(self));
}

static void PLXScrollViewDidMoveToWindow(UIScrollView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigScrollMoveToWindow)(self, _cmd);
    if (!PLXHidesScrollBars(self)) return;
    if (self.showsVerticalScrollIndicator) self.showsVerticalScrollIndicator = NO;
    if (self.showsHorizontalScrollIndicator) self.showsHorizontalScrollIndicator = NO;
}

__attribute__((constructor)) static void PLXInstallContentUnderBar(void) {
    Method layout = class_getInstanceMethod(UITableView.class, @selector(layoutSubviews));
    PLXOrigTableLayout = method_setImplementation(layout, (IMP)PLXTableLayoutSubviews);

    Class scroll = UIScrollView.class;
    PLXOrigSetShowsVertical = method_setImplementation(class_getInstanceMethod(scroll, @selector(setShowsVerticalScrollIndicator:)), (IMP)PLXSetShowsVertical);
    PLXOrigSetShowsHorizontal = method_setImplementation(class_getInstanceMethod(scroll, @selector(setShowsHorizontalScrollIndicator:)), (IMP)PLXSetShowsHorizontal);
    SEL move = @selector(didMoveToWindow);
    Method moveMethod = class_getInstanceMethod(scroll, move);
    // Add an override on UIScrollView itself so UIView's implementation is never replaced.
    if (class_addMethod(scroll, move, (IMP)PLXScrollViewDidMoveToWindow, method_getTypeEncoding(moveMethod))) {
        PLXOrigScrollMoveToWindow = method_getImplementation(class_getInstanceMethod(UIView.class, move));
    } else {
        PLXOrigScrollMoveToWindow = method_setImplementation(moveMethod, (IMP)PLXScrollViewDidMoveToWindow);
    }
}
