//
//  TBHotKey.m
//

#import "TBHotKey.h"

static OSStatus TBHotKeyHandler(EventHandlerCallRef nextHandler,
                                EventRef event, void *userData);

@interface TBHotKey ()
@property (nonatomic, assign) EventHotKeyRef hotKeyRef;
@property (nonatomic, assign) EventHandlerRef handlerRef;
@property (nonatomic, assign) UInt32 hotKeyID;
@property (nonatomic, copy) void (^handler)(void);
@end

@implementation TBHotKey

- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)modifiers
                        handler:(void (^)(void))handler {
    if ((self = [super init])) {
        _handler = [handler copy];
        static UInt32 sNextID = 1;
        _hotKeyID = sNextID++;

        EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
        InstallEventHandler(GetApplicationEventTarget(), TBHotKeyHandler,
                            1, &type, (__bridge void *)self, &_handlerRef);

        EventHotKeyID hkID = { 'TBHK', _hotKeyID };
        OSStatus st = RegisterEventHotKey(keyCode, modifiers, hkID,
                                          GetApplicationEventTarget(), 0, &_hotKeyRef);
        if (st != noErr) {
            fprintf(stderr, "[tb] hotkey register failed: %d\n", (int)st);
            _hotKeyRef = NULL;
        }
    }
    return self;
}

- (void)unregister {
    if (self.hotKeyRef) { UnregisterEventHotKey(self.hotKeyRef); self.hotKeyRef = NULL; }
    if (self.handlerRef) { RemoveEventHandler(self.handlerRef); self.handlerRef = NULL; }
}

- (void)dealloc { [self unregister]; }

@end

static OSStatus TBHotKeyHandler(EventHandlerCallRef nextHandler,
                                EventRef event, void *userData) {
    EventHotKeyID hkID;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                      NULL, sizeof(hkID), NULL, &hkID);
    TBHotKey *self_ = (__bridge TBHotKey *)userData;
    if (self_ && hkID.id == self_.hotKeyID) {
        void (^h)(void) = self_.handler;
        if (h) h();
        return noErr;
    }
    return eventNotHandledErr;
}
