//
//  AppDelegate.m
//  hostedwindow
//
//

#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "CAPluginLayer.h"

@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSSegmentedControl *displayControl;
@property (weak) IBOutlet NSSegmentedControl *processControl;

@end

@implementation AppDelegate {
    // overall screen layout
    NSRect _screensBounds;
    CGFloat _screensVOffset;
    
    NSPoint _previousMousePos;
    
    NSMutableDictionary<NSNumber*, CALayer*> *_windows;
    
    BOOL _showDesktop;
    BOOL _showOutlines;
}

// resize and position root layer within window
// NOTE: not entirely correct because it fights and overrides what the NSView is trying do to it
- (void)layoutSublayersOfLayer:(CALayer *)layer {
    const CGSize size = _window.contentView.bounds.size;
    const float scale = MIN(size.height/_screensBounds.size.height, size.width/_screensBounds.size.width);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.position = CGPointMake((size.width-_screensBounds.size.width*scale)/2, (size.height-_screensBounds.size.height*scale)/2); // center
    layer.bounds = _screensBounds;
    layer.transform = CATransform3DMakeScale(scale, scale, 1);
    [CATransaction commit];
}

- (void)showDisplay:(NSInteger)idx { // out-of-range for 'all'
    NSArray<NSScreen *> *screens = [NSScreen screens];
    assert(screens.count > 0);
    NSRect bounds = screens[0].frame;
    _screensVOffset = bounds.size.height;
    for(int i = 1; i < screens.count; i++) {
        bounds = NSUnionRect(bounds, screens[i].frame);
    }
    if(idx >= 0 && idx < screens.count) {
        _screensBounds  = screens[idx].frame;
    } else {
        _screensBounds = bounds;
    }
    
    // force window aspect ratio
    _window.contentAspectRatio = _screensBounds.size;
    // resize window so as to preserve number of pixels
    CGSize size = _window.contentView.bounds.size;
    float scale = sqrt(size.width*size.height/(_screensBounds.size.width*_screensBounds.size.height));
    [_window setContentSize:NSMakeSize(_screensBounds.size.width*scale, _screensBounds.size.height*scale)];
    
    CALayer *root = _window.contentView.layer;
    [root setNeedsLayout];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if(menu ==  [_displayControl menuForSegment:0]) {
        [self updateDisplayMenu];
    } else if(menu ==  [_processControl menuForSegment:0]) {
        [self updateProcessMenu];
    }
}

#pragma mark -
#pragma mark process menu
- (NSSet*)selectedProcesses { // nil means ALL
    NSMenu *menu = [_processControl menuForSegment:0];
    
    NSMutableSet *set = [NSMutableSet set];
    for(NSMenuItem *item in menu.itemArray) {
        if(item.state == NSControlStateValueOn) [set addObject:@(item.tag)];
    }
    return ([set count] == 0 || [set containsObject:@(-1)]) ? nil : set;
}

- (void)doProcessSelect:(NSMenuItem*)sender {
    NSMenu *menu = [_processControl menuForSegment:0];
    
    sender.state = (sender.state == NSControlStateValueOn)?NSControlStateValueOff:NSControlStateValueOn; // toggle
    
    if(sender.state == NSControlStateValueOn && sender.tag != -1) { // disable 'all' if select something else
        for(NSMenuItem *item in menu.itemArray) {
            if(item.tag == -1) item.state = NSControlStateValueOff;
        }
    }
    [self updateWindowsReload:NO];
}

- (void)updateProcessMenu {
    NSMenu *menu = [_processControl menuForSegment:0];

    // collect info
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | (_showDesktop?0:kCGWindowListExcludeDesktopElements), kCGNullWindowID); // PERFORMANCE: slow
    const CFIndex n = CFArrayGetCount(windowList);
    for(CFIndex i = 0; i < n; i++) {
        CFDictionaryRef windowInfo =  CFArrayGetValueAtIndex(windowList, i);
        
        pid_t ownerPID = [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID) unsignedIntValue];
        if(ownerPID ==  getpid()) continue; // skip self
        
        CGRect rect = CGRectZero;
        CGRectMakeWithDictionaryRepresentation(CFDictionaryGetValue(windowInfo, kCGWindowBounds), &rect);
        rect.origin.y = _screensVOffset - (rect.origin.y+rect.size.height); // vflip and offset coordinate system
        if(!NSContainsRect(_screensBounds, rect)) continue; // skip offscreen
        
        CGFloat windowAlpha =  [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowAlpha) floatValue];
        if(windowAlpha == 0) continue; // skip invisible
        
        int windowLayer = [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowLayer) unsignedIntValue];
        if(windowLayer <= INT_MIN+22) continue; // skip - Some sort of WindowServer thing, one for each display - renders corrupt?
        
        NSMutableDictionary *props = dict[@(ownerPID)];
        if(!props) {
            props = [NSMutableDictionary dictionary];
            props[@"name"] = (__bridge NSString*)CFDictionaryGetValue(windowInfo, kCGWindowOwnerName);
            props[@"count"] = 0;
            [dict setObject:props forKey:@(ownerPID)];
        }
        props[@"count"] = @([(NSNumber*)props[@"count"] intValue] +1);
    }
    
    NSSet *processSet = [self selectedProcesses];

    [menu removeAllItems];
    NSMenuItem *item = [menu addItemWithTitle:@"All Processes" action:@selector(doProcessSelect:) keyEquivalent:@""];
    item.state = processSet?NSControlStateValueOff:NSControlStateValueOn;
    item.tag = -1;
    for(NSNumber *pid in [dict allKeys]) {
        NSDictionary *props = dict[pid];
        NSString *title = [NSString stringWithFormat:@"%@: %@ x%@", pid, props[@"name"], props[@"count"]];
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(doProcessSelect:) keyEquivalent:@""];
        item.state = [processSet containsObject:pid]?NSControlStateValueOn:NSControlStateValueOff;
        item.tag = [pid intValue];
        
        NSSize iconSize = NSMakeSize(20, 20);
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:[pid intValue]];
        NSImage *image = app.icon;
        [image setSize:iconSize];
        if(!image) image = [[NSImage alloc] initWithSize:iconSize]; // empty place holder
        item.image = image;
    }
}

#pragma mark -
#pragma mark display menu
- (int)selectedDisplay {
    NSMenu *menu = [_displayControl menuForSegment:0];
    int tag = -1;
    for(NSMenuItem *item in menu.itemArray) {
        if(item.state == NSControlStateValueOn) tag = (int)item.tag;
    }
    return tag;
}

- (void)doDisplaySelect:(NSMenuItem*)sender {
    NSMenu *menu = [_displayControl menuForSegment:0];
    for(NSMenuItem *item in menu.itemArray) {
        item.state = (item == sender)?NSControlStateValueOn:NSControlStateValueOff; // ensure only ONE is selected
    }
    [self showDisplay:[self selectedDisplay]];
}

- (void)updateDisplayMenu {
    NSMenu *menu = [_displayControl menuForSegment:0];
    
    NSArray<NSScreen *> *screens = [NSScreen screens];
    assert(screens.count > 0);
    NSRect bounds = screens[0].frame;
    for(int i = 1; i < screens.count; i++) {
        bounds = NSUnionRect(bounds, screens[i].frame);
    }
    
    // current selection
    int tag = [self selectedDisplay];
    if(tag > screens.count-1) tag = -1; // reset
    if(screens.count == 1) tag = 0;
    
    // image generation config
    NSSize iconSize = NSMakeSize(20, 20);
    CGFloat scale = MIN(iconSize.height/bounds.size.height, iconSize.width/bounds.size.width);
    NSPoint offset = NSMakePoint((iconSize.width-bounds.size.width*scale)/2, (iconSize.height-bounds.size.height*scale)/2);
    
    NSAffineTransform *trans = [NSAffineTransform transform];
    [trans translateXBy:offset.x-bounds.origin.x yBy:offset.y-bounds.origin.y];
    [trans scaleBy:MIN(iconSize.height/bounds.size.height, iconSize.width/bounds.size.width)];
    
    // regenerate menu
    [menu removeAllItems];
    if(screens.count != 1) { // when one screen show "Display 1:..", when multiple screens show "All, Display 1:, Display 2:.."
        NSMenuItem *item = [menu addItemWithTitle:[NSString stringWithFormat:@"All Displays: %dx%d", (int)bounds.size.width, (int)bounds.size.height] action:@selector(doDisplaySelect:) keyEquivalent:@""];
        item.state =  item.state = (tag == -1)?NSControlStateValueOn:NSControlStateValueOff;
        item.tag = -1;
    }
    for(int i = 0; i < (int)screens.count; i++) {
        NSSize ssize = screens[i].frame.size;
        NSString * title = [NSString stringWithFormat:@"Display %d: %dx%d", i+1, (int)ssize.width, (int)ssize.height];
        
        NSImage *image = [[NSImage alloc] initWithSize:iconSize];
        [image lockFocus];
        [[NSColor blackColor] setStroke];
        [[NSColor grayColor] setFill];
        for(int j = 0; j < screens.count; j++) {
            NSRect rect = screens[j].frame;
            rect.origin = [trans transformPoint:rect.origin];
            rect.size = [trans transformSize:rect.size];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
            if(i == j) [path fill];
            [path stroke];
        }
        [image unlockFocus];
        
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(doDisplaySelect:) keyEquivalent:@""];
        //item.image = image;
        item.state = (tag == i)?NSControlStateValueOn:NSControlStateValueOff;
        item.tag = i;
    }
}

#pragma mark -

- (void)updateWindowsReload:(BOOL)reload {
    CALayer *root = _window.contentView.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    if(reload) {
        // destroy all existing windows
        for(NSNumber *key in [_windows allKeys]) {
            [_windows[key] removeFromSuperlayer];
        }
        [_windows removeAllObjects];
    }
    
    NSSet *processSet = [self selectedProcesses];
    
    NSMutableSet<NSNumber*> *previousWindows = [NSMutableSet setWithArray:[_windows allKeys]];
    
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | (_showDesktop?0:kCGWindowListExcludeDesktopElements), kCGNullWindowID); // PERFORMANCE: slow
    const CFIndex n = CFArrayGetCount(windowList);
    for(CFIndex i = 0; i < n; i++) {
        CFDictionaryRef windowInfo =  CFArrayGetValueAtIndex(windowList, i);
        
        pid_t ownerPID = [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID) unsignedIntValue];
        if(ownerPID == getpid()) continue; // skip self
        if(processSet && ![processSet containsObject:@(ownerPID)]) continue; // skip processes
        
        CGWindowID windowID = [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowNumber) unsignedIntValue];
        
        CGRect rect = CGRectZero;
        CGRectMakeWithDictionaryRepresentation(CFDictionaryGetValue(windowInfo, kCGWindowBounds), &rect);
        rect.origin.y = _screensVOffset - (rect.origin.y+rect.size.height); // vflip and offset coordinate system
        if(!NSContainsRect(_screensBounds, rect)) continue; // skip offscreen
        
        CGFloat windowAlpha =  [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowAlpha) floatValue];
        if(windowAlpha == 0) continue; // skip invisible
        
        int windowLayer = [(__bridge NSNumber*)CFDictionaryGetValue(windowInfo, kCGWindowLayer) unsignedIntValue];
        if(windowLayer <= INT_MIN+22) continue; // skip - Some sort of WindowServer thing, one for each display - renders corrupt?
        
        NSNumber *key = @(windowID);
        CALayer *layer = _windows[key];
        if(layer) {
            // move
            [previousWindows removeObject:key];
        } else {
            // create
            if(!_showOutlines) {
                CAPluginLayer *plug = [CAPluginLayer layer];
                plug.pluginType = kCAPluginLayerTypeCGSWindow;
                plug.pluginId = windowID;
                plug.masksToBounds = YES; // Helps avoid some out-of-bounds rendering artifacts on 10.9.5
                layer = plug;
            }
            
            if(!layer) { // ie. CAPluginLayer returns nil
                layer = [CALayer layer];
                layer.backgroundColor = [[NSColor orangeColor] colorWithAlphaComponent:0.2].CGColor;
                layer.borderColor = [NSColor yellowColor].CGColor;
                layer.borderWidth = 2;
            }
            
            layer.anchorPoint = CGPointMake(0, 0); // use bottom-left of window
            [root addSublayer:layer];
            [_windows setObject:layer forKey:key];
        }
        
        layer.zPosition = -i;
        layer.bounds    = CGRectMake(0, 0, rect.size.width, rect.size.height);
        layer.position  = rect.origin;
    }
    CFRelease(windowList);
    
    if(!_showDesktop) {
        // add screens as fake windows
        NSArray<NSScreen*> *screens = [NSScreen screens];
        for(int i = 0; i < screens.count; i++) {
            NSScreen *screen = screens[i];
            NSRect rect = screen.frame;
            if(!NSContainsRect(_screensBounds, rect)) continue;
            
            NSNumber *key = @(i + 0xFFFF000);
            CALayer *layer = _windows[key];
            if(layer) {
                // move
                [previousWindows removeObject:key];
            } else {
                // create
                layer = [CALayer layer];
                layer.anchorPoint = CGPointMake(0, 0); // use bottom-left of window
                layer.backgroundColor = [NSColor colorWithCalibratedRed:0.33 green:0.61 blue:0.85 alpha:1.].CGColor;
                layer.borderColor = [NSColor blackColor].CGColor;
                layer.borderWidth = 2;
                [root addSublayer:layer];
                [_windows setObject:layer forKey:key];
            }
            
            layer.zPosition = -n;
            layer.bounds    = CGRectMake(0, 0, rect.size.width, rect.size.height);
            layer.position  = rect.origin;
        }
    }
    
    {   // mouse
        NSPoint pos = [NSEvent mouseLocation];
        NSCursor *cursor = [NSCursor currentSystemCursor]; // PERFORMANCE: slow
        NSImage *nsimage = cursor.image;
        if(nsimage) {
            NSPoint offset = cursor.hotSpot;
            // https://stackoverflow.com/questions/14510870/how-to-programatically-change-the-cursor-size-on-a-mac?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa
            NSDictionary *dict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.apple.universalaccess"];
            CGFloat cursorScale = MAX(1, [[dict objectForKey:@"mouseDriverCursorSize"] floatValue]);
            
            NSSize size = nsimage.size;
            if(cursorScale > 1) {
                size.width  *= cursorScale;
                size.height *= cursorScale;
                offset.x *= cursorScale;
                offset.y *= cursorScale;
            }
            CGRect rect = CGRectMake(pos.x - offset.x, pos.y - size.height + offset.y, size.width, size.height);
            
            NSNumber *key = @(0xFFFFFFFF);
            CALayer *layer = _windows[key];
            if(layer) {
                // move
                [previousWindows removeObject:key];
            } else {
                // create
                layer = [CALayer layer];
                layer.anchorPoint = CGPointMake(0, 0); // use bottom-left of window
                [root addSublayer:layer];
                [_windows setObject:layer forKey:key];
            }
            
            layer.zPosition = 1;
            layer.bounds    = CGRectMake(0, 0, rect.size.width, rect.size.height);
            layer.position  = rect.origin;
            
            NSRect proposedRect = NSMakeRect(0, 0, size.width, size.height);
            layer.contents = (__bridge id)[nsimage CGImageForProposedRect:&proposedRect context:NULL hints:NULL];
        }
    }
    
    for(NSNumber *key in previousWindows) {
        // close
        [_windows[key] removeFromSuperlayer];
        [_windows removeObjectForKey:key];
    }
    
    [CATransaction commit];
}

#pragma mark -

- (void)didChangeScreenParameters:(NSNotification*)notification {
    [self showDisplay:[self selectedDisplay]];
}

- (void)didChangeWindows:(id)sender {
    [self updateWindowsReload:NO];
}

- (void)pollWindows:(id)sender {
    // only update if the mouse has moved...  which is mostly reasonable
    NSPoint pos = [NSEvent mouseLocation];
    if(!NSEqualPoints(pos, _previousMousePos)) {
        _previousMousePos = pos;
        [self updateWindowsReload:NO];
    }
}

- (IBAction)toggleDesktop:(id)sender {
    _showDesktop = !_showDesktop;
    [self updateWindowsReload:NO];
}

- (IBAction)toggleOutlines:(id)sender {
    _showOutlines = !_showOutlines;
    [self updateWindowsReload:YES];
}

#pragma mark -

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // toolbar menus
    NSMenu *displayMenu = [[NSMenu alloc] init];
    displayMenu.delegate = (id<NSMenuDelegate>)self;
    [_displayControl setMenu:displayMenu forSegment:0]; // configured as momentary
    if([_displayControl respondsToSelector:@selector(setShowsMenuIndicator:forSegment:)]) [_displayControl setShowsMenuIndicator:YES forSegment:0]; // 10.13+
  
    NSMenu *processMenu = [[NSMenu alloc] init];
    processMenu.delegate = (id<NSMenuDelegate>)self;
    [_processControl setMenu:processMenu forSegment:0]; // configured as momentary
    if([_processControl respondsToSelector:@selector(setShowsMenuIndicator:forSegment:)]) [_processControl setShowsMenuIndicator:YES forSegment:0]; // 10.13+

    
    _window.backgroundColor = [NSColor grayColor];
    
    CALayer *root = [CALayer layer];
    root.backgroundColor = [NSColor grayColor].CGColor;
    root.anchorPoint = CGPointMake(0, 0);
    root.masksToBounds = YES;
    root.layoutManager = (id<CALayoutManager>)self;
    NSView *view = _window.contentView;
    view.layer = root;
    view.wantsLayer = YES; // layer hosted
    
    _window.collectionBehavior = NSWindowCollectionBehaviorStationary;
    
    _showDesktop = YES;
    _windows = [NSMutableDictionary dictionary];
    
    // watch screen changes
    [[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(didChangeScreenParameters:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [self didChangeScreenParameters:nil]; // initial check
    
    // watch focus changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeWindows:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeWindows:) name:NSWorkspaceDidDeactivateApplicationNotification object:nil];

    // is there an API to listen for window position changes.. no? just poll it then
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(pollWindows:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
}

@end
