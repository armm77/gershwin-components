/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "X11Support.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/keysym.h>
// Synthetic input is injected with XSendEvent. GNUstep's X backend does not
// filter synthetic events; the reason naive XSendEvent appears to do nothing is
// that the event must name the GNUstep content window (the one carrying
// _GNUSTEP_WM_ATTR), not the window-manager frame that reparents it — the backend
// looks the target up in its own window table (XGServerEvent.m). We therefore
// resolve the GNUstep window under the pointer (for clicks) or holding input
// focus (for keys) and address the event to it. XKB is used to find the shift
// level for a character's keysym. This input path is X11-only; a Wayland session
// would need a different backend.
#import <X11/XKBlib.h>
#include <unistd.h>

@implementation X11Support

static Display *display = NULL;

// How long to hold a synthetic button press before releasing it, so the press
// and release are not coalesced into a single zero-duration event.
static const useconds_t kPressHoldMicroseconds = 40000;  // 40 ms

// Xlib's default error handler calls exit() on any protocol error, which would
// take down this long-running automation server. A few codes are expected
// during automation — e.g. a BadWindow/BadDrawable/BadMatch from racing a window
// that closes mid-request — and are swallowed. Anything else is logged loudly
// but still tolerated, so genuine bugs stay visible without crashing the server.
static int NonFatalXError(Display *dpy, XErrorEvent *e) {
    switch (e->error_code) {
        case BadWindow:
        case BadDrawable:
        case BadMatch:
            NSDebugLLog(@"gwcomp", @"[X11Support] ignored transient X error %d (request %d)",
                        e->error_code, e->request_code);
            return 0;
        default:
            break;
    }
    char buf[256];
    XGetErrorText(dpy, e->error_code, buf, sizeof(buf));
    NSLog(@"[X11Support] X protocol error: %s (code %d, request %d) — continuing",
          buf, e->error_code, e->request_code);
    return 0;
}

+ (Display *)display {
    if (!display) {
        XSetErrorHandler(NonFatalXError);
        display = XOpenDisplay(NULL);
        if (!display) {
            NSDebugLLog(@"gwcomp", @"[X11Support] Failed to open X display");
        }
    }
    return display;
}

+ (void)cleanup {
    if (display) {
        XCloseDisplay(display);
        display = NULL;
    }
}

+ (NSArray *)windowList {
    Display *d = [self display];
    if (!d) return @[];

    Window root = DefaultRootWindow(d);
    Window parent;
    Window *children = NULL;
    unsigned int nchildren = 0;

    NSMutableArray *result = [NSMutableArray array];

    if (XQueryTree(d, root, &root, &parent, &children, &nchildren)) {
        for (unsigned int i = 0; i < nchildren; i++) {
            [result addObject:@(children[i])];
        }
        if (children) XFree(children);
    }

    return result;
}

+ (NSDictionary *)windowInfo:(unsigned long)xid {
    Display *d = [self display];
    if (!d) return nil;

    Window w = (Window)xid;
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(d, w, &attrs)) {
        return nil;
    }

    // Get Property: _NET_WM_NAME or WM_NAME
    NSString *title = @"";
    char *name = NULL;
    if (XFetchName(d, w, &name) && name) {
        title = [NSString stringWithUTF8String:name];
        XFree(name);
    }

    // Get PID: _NET_WM_PID
    unsigned long pid = 0;
    Atom atomPID = XInternAtom(d, "_NET_WM_PID", True);
    if (atomPID != None) {
        Atom actualType;
        int actualFormat;
        unsigned long nItems;
        unsigned long bytesAfter;
        unsigned char *propPID = NULL;
        if (XGetWindowProperty(d, w, atomPID, 0, 1, False, XA_CARDINAL,
                               &actualType, &actualFormat, &nItems, &bytesAfter, &propPID) == Success) {
            if (propPID) {
                pid = *((unsigned long *)propPID);
                XFree(propPID);
            }
        }
    }

    return @{
        @"id": @(w),
        @"x": @(attrs.x),
        @"y": @(attrs.y),
        @"width": @(attrs.width),
        @"height": @(attrs.height),
        @"map_state": @(attrs.map_state), // IsViewable=2
        @"title": title,
        @"pid": @(pid)
    };
}

// True if the window carries _GNUSTEP_WM_ATTR. GNUstep sets this on every content
// window it creates, unconditionally (XGServerWindow.m), so it is the reliable
// marker of "a window the GNUstep backend will recognise" — unlike _NET_WM_PID,
// which is only set under an EWMH window manager and is also copied onto the frame.
static Bool HasGNUstepAttr(Display *d, Window w) {
    static Atom attr = None;
    if (attr == None) attr = XInternAtom(d, "_GNUSTEP_WM_ATTR", False);
    Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL;
    if (XGetWindowProperty(d, w, attr, 0, 1, False, AnyPropertyType,
                           &type, &fmt, &n, &after, &data) != Success)
        return False;
    Bool has = (type != None);
    if (data) XFree(data);
    return has;
}

// Resolve the GNUstep content window under root point (x,y) and the point in that
// window's coordinates. Descends from root with XTranslateCoordinates to the
// deepest window under the point, remembering the deepest one bearing
// _GNUSTEP_WM_ATTR (the actual GNUstep window, not the reparenting WM frame).
// Falls back to the leaf window if none qualifies (bare server / non-GNUstep app).
static Window ResolveWindowAt(Display *d, int x, int y, int *outX, int *outY) {
    Window root = DefaultRootWindow(d);
    Window cur = root, chosen = None;
    int curX = x, curY = y, chX = x, chY = y;
    for (;;) {
        Window child = None;
        int dx = 0, dy = 0;
        if (!XTranslateCoordinates(d, root, cur, x, y, &dx, &dy, &child))
            break;
        curX = dx; curY = dy;                 // point in cur's coordinates
        if (cur != root && HasGNUstepAttr(d, cur)) {
            chosen = cur; chX = curX; chY = curY;
        }
        if (child == None) break;
        cur = child;
    }
    if (chosen == None) { chosen = cur; chX = curX; chY = curY; }
    *outX = chX; *outY = chY;
    return chosen;
}

// First GNUstep content window at or below w (depth first), or None.
static Window FindGNUstepWindowBelow(Display *d, Window w) {
    if (HasGNUstepAttr(d, w)) return w;
    Window root, parent, *kids = NULL;
    unsigned int n = 0;
    Window found = None;
    if (XQueryTree(d, w, &root, &parent, &kids, &n)) {
        for (unsigned int i = 0; i < n && found == None; i++)
            found = FindGNUstepWindowBelow(d, kids[i]);
        if (kids) XFree(kids);
    }
    return found;
}

// The GNUstep window that should receive keyboard input. X delivers a key event
// to the client owning the addressed window, and GNUstep then routes it to its
// own key window (XGServerEvent.m:2231) — so the event must be addressed to a
// GNUstep-owned window, or the app's process never sees it. Prefer the input-focus
// window (set by activateWindow), descending into it for the GNUstep child when
// the frame itself holds focus; fall back to the window under the pointer.
static Window ResolveKeyTarget(Display *d) {
    Window focus = None;
    int revert = 0;
    XGetInputFocus(d, &focus, &revert);
    if (focus != None && focus != PointerRoot) {
        Window w = FindGNUstepWindowBelow(d, focus);
        if (w != None) return w;
    }
    Window root = DefaultRootWindow(d), r, child;
    int rx = 0, ry = 0, wx = 0, wy = 0;
    unsigned int mask = 0;
    if (XQueryPointer(d, root, &r, &child, &rx, &ry, &wx, &wy, &mask)) {
        int ox, oy;
        Window w = ResolveWindowAt(d, rx, ry, &ox, &oy);
        if (w != None) return w;
    }
    return focus;
}

// A real X server timestamp. GNUstep compares successive click times to detect
// multi-clicks (XGServerEvent.m:433); CurrentTime (0) would make every click look
// like a first click, so we round-trip a zero-length property append on a private
// window and read the timestamp the server stamps on the resulting PropertyNotify.
static Bool MatchTimestamp(Display *d, XEvent *e, XPointer arg) {
    return (e->type == PropertyNotify && e->xproperty.atom == *(Atom *)arg) ? True : False;
}
static Time ServerTime(Display *d) {
    static Window win = None;
    static Atom atom = None;
    if (win == None) {
        win = XCreateWindow(d, DefaultRootWindow(d), -10, -10, 1, 1, 0,
                            CopyFromParent, InputOnly, CopyFromParent, 0, NULL);
        XSelectInput(d, win, PropertyChangeMask);
        atom = XInternAtom(d, "_UIBRIDGE_TIMESTAMP", False);
    }
    XChangeProperty(d, win, atom, XA_CARDINAL, 8, PropModeAppend,
                    (unsigned char *)"", 0);
    XEvent e;
    XIfEvent(d, &e, MatchTimestamp, (XPointer)&atom);
    return e.xproperty.time;
}

static void SendButton(Display *d, Window w, int wx, int wy, int rx, int ry,
                       Bool press, unsigned int button, unsigned int state, Time t) {
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.type = press ? ButtonPress : ButtonRelease;
    e.xbutton.send_event = True;
    e.xbutton.display = d;
    e.xbutton.window = w;
    e.xbutton.root = DefaultRootWindow(d);
    e.xbutton.subwindow = None;
    e.xbutton.time = t;
    e.xbutton.x = wx; e.xbutton.y = wy;
    e.xbutton.x_root = rx; e.xbutton.y_root = ry;
    e.xbutton.state = state;
    e.xbutton.button = button;
    e.xbutton.same_screen = True;
    XSendEvent(d, w, True, press ? ButtonPressMask : ButtonReleaseMask, &e);
}

static void SendKey(Display *d, Window w, KeyCode code,
                    Bool press, unsigned int state, Time t) {
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.type = press ? KeyPress : KeyRelease;
    e.xkey.send_event = True;
    e.xkey.display = d;
    e.xkey.window = w;
    e.xkey.root = DefaultRootWindow(d);
    e.xkey.subwindow = None;
    e.xkey.time = t;
    e.xkey.x = 1; e.xkey.y = 1;
    e.xkey.x_root = 0; e.xkey.y_root = 0;
    e.xkey.state = state;
    e.xkey.keycode = code;
    e.xkey.same_screen = True;
    XSendEvent(d, w, True, press ? KeyPressMask : KeyReleaseMask, &e);
}

+ (void)simulateMouseMoveTo:(NSPoint)point {
    Display *d = [self display];
    if (!d) return;
    // Move the real pointer so callers can position the cursor (hover) and so a
    // subsequent click resolves the window under this location. Assumes screen 0.
    Window root = DefaultRootWindow(d);
    XWarpPointer(d, None, root, 0, 0, 0, 0, (int)point.x, (int)point.y);
    XSync(d, False);
}

+ (void)simulateClick:(int)button {
    Display *d = [self display];
    if (!d) return;
    Window root = DefaultRootWindow(d), r, child;
    int rx = 0, ry = 0, wx = 0, wy = 0;
    unsigned int mask = 0;
    if (!XQueryPointer(d, root, &r, &child, &rx, &ry, &wx, &wy, &mask)) return;

    int tx, ty;
    Window target = ResolveWindowAt(d, rx, ry, &tx, &ty);
    Time t = ServerTime(d);
    unsigned int bmask = (button == 1) ? Button1Mask :
                         (button == 2) ? Button2Mask :
                         (button == 3) ? Button3Mask : 0;
    SendButton(d, target, tx, ty, rx, ry, True, (unsigned int)button, 0, t);
    XFlush(d);
    usleep(kPressHoldMicroseconds);  // hold so press/release aren't coalesced
    SendButton(d, target, tx, ty, rx, ry, False, (unsigned int)button, bmask, t + 1);
    XSync(d, False);
}

+ (void)activateWindow:(unsigned long)xid {
    Display *d = [self display];
    if (!d || xid == 0) return;
    Window w = (Window)xid;
    Window root = DefaultRootWindow(d);

    // Standard EWMH request: ask the window manager to activate the window.
    // Source indication 2 ("pager") is the value WMs honour for automation; it
    // bypasses the focus-stealing prevention that ignores an application's own
    // (source 1) activation requests.
    Atom netActive = XInternAtom(d, "_NET_ACTIVE_WINDOW", False);
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.type = ClientMessage;
    e.xclient.window = w;
    e.xclient.message_type = netActive;
    e.xclient.format = 32;
    e.xclient.data.l[0] = 2;            // source indication: pager / automation
    e.xclient.data.l[1] = CurrentTime;
    XSendEvent(d, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &e);

    // Fallback for WMs that ignore EWMH (or a bare server with no WM): raise the
    // top-level frame (walk up to the child of root) and set input focus on the
    // client window directly.
    Window cur = w, parent = w, retRoot = root, *children = NULL;
    unsigned int n = 0;
    while (XQueryTree(d, cur, &retRoot, &parent, &children, &n)) {
        if (children) { XFree(children); children = NULL; }
        if (parent == retRoot || parent == 0) break;
        cur = parent;
    }
    XRaiseWindow(d, cur);
    XSetInputFocus(d, w, RevertToParent, CurrentTime);
    XFlush(d);
}

// The keysym for a control char or, for printable ASCII/Latin-1, the codepoint
// itself (those keysyms equal the Unicode value). Returns NoSymbol if the
// character has no single keysym this way (e.g. emoji / CJK).
static KeySym KeysymForChar(unichar c) {
    switch (c) {
        case '\n': case '\r': return XK_Return;
        case '\t': return XK_Tab;
        case 0x1b: return XK_Escape;
        case 0x08: case 0x7f: return XK_BackSpace;
    }
    if (c >= 0x20 && c <= 0xff) return (KeySym)c;
    return NoSymbol;
}

+ (void)simulateKeyStroke:(NSString *)keyString {
    Display *d = [self display];
    if (!d) return;
    Window target = ResolveKeyTarget(d);
    if (target == None) return;

    Time t = ServerTime(d);
    NSUInteger len = [keyString length];
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [keyString characterAtIndex:i];
        uint32_t scalar = c;
        // Combine a UTF-16 surrogate pair into one Unicode scalar (e.g. emoji).
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < len) {
            unichar lo = [keyString characterAtIndex:i + 1];
            if (lo >= 0xdc00 && lo <= 0xdfff) {
                scalar = 0x10000 + (((uint32_t)c - 0xd800) << 10) + ((uint32_t)lo - 0xdc00);
                i++;
            }
        }

        // Characters that exist on the active layout are typed directly. When the
        // character sits on the keycode's shifted level, set ShiftMask in the
        // event's state so GNUstep's character lookup picks the shifted symbol
        // (so 'A', '!', '?', ':' come out right, not their unshifted twin).
        KeySym sym = (scalar <= 0xffff) ? KeysymForChar((unichar)scalar) : NoSymbol;
        KeyCode code = (sym != NoSymbol) ? XKeysymToKeycode(d, sym) : 0;
        if (code != 0) {
            Bool needShift = (XkbKeycodeToKeysym(d, code, 0, 0) != sym &&
                              XkbKeycodeToKeysym(d, code, 0, 1) == sym);
            unsigned int st = needShift ? ShiftMask : 0;
            SendKey(d, target, code, True, st, t); t++;
            SendKey(d, target, code, False, st, t); t++;
            XFlush(d);
            continue;
        }

        // Characters with no key on the active layout (accented Latin, CJK, emoji)
        // are not expressible by keycode and are skipped here.
        NSDebugLLog(@"gwcomp", @"[X11Support] no layout key for character U+%04X", scalar);
    }
    XSync(d, False);
}

@end
