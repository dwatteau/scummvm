/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

// Disable symbol overrides so that we can use system headers
#define FORBIDDEN_SYMBOL_ALLOW_ALL
#include "common/scummsys.h"

#if defined(MACOSX) && defined(USE_SYSDIALOGS)

#include "backends/dialogs/macosx/macosx-dialogs.h"

#include "common/config-manager.h"
#include "common/algorithm.h"
#include "common/translation.h"

#include <AvailabilityMacros.h>
#include <AppKit/NSNibDeclarations.h>
#include <AppKit/NSOpenPanel.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSButton.h>
#include <Foundation/NSString.h>
#include <Foundation/NSURL.h>
#include <Foundation/NSThread.h>
#include <Foundation/NSAutoreleasePool.h>

// From the 10.6 SDK:
// "This method was published in 10.6, but has existed since 10.4."
//
// This means that the feature works on 10.4/10.5 as well, but their SDK
// headers didn't expose it at all. I've checked that it does work at runtime,
// but we stil keep some respondsToSelector safety calls below, in case its
// symbols were only added in some later 10.4 update or something.
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1060
@interface NSSavePanel(Undocumented)
- (BOOL)showsHiddenFiles;
- (void)setShowsHiddenFiles:(BOOL)flag;
@end
#endif

#if MAC_OS_X_VERSION_MIN_REQUIRED < 101400

    #ifndef NSControlStateValueOff
      #define NSControlStateValueOff NSOffState
    #endif

    #ifndef NSControlStateValueOn
      #define NSControlStateValueOn NSOnState
    #endif

#define NSButtonTypeSwitch NSSwitchButton
#endif


@interface BrowserDialogPresenter : NSObject {
@public
	NSURL *_url;
	BOOL _isDirBrowser;
	CFStringRef _title;
	CFStringRef _prompt;
@private
	NSOpenPanel *_panel;
}
- (id) init;
- (void) dealloc;
- (void) showOpenPanel;
- (IBAction) showHiddenFiles : (id) sender;
@end

@implementation BrowserDialogPresenter

- (id) init {
	self = [super init];
	_url = nil;
	_isDirBrowser = NO;
	_title = nullptr;
	_prompt = nullptr;
	_panel = nil;
	return self;
}

- (void) dealloc {
	[_url release];

	if (_title)
		CFRelease(_title);

	if (_prompt)
		CFRelease(_prompt);

	[super dealloc];
}

- (void) showOpenPanel {
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	_panel = panel;

	[panel setCanChooseFiles: !_isDirBrowser];
	[panel setCanChooseDirectories: _isDirBrowser];
	if (_isDirBrowser)
		[panel setTreatsFilePackagesAsDirectories:YES];

	if (_title)
		[panel setTitle:(NSString *)_title];

	if (_prompt)
		[panel setPrompt:(NSString *)_prompt];

	NSButton *showHiddenFilesButton = nil;
	// note: still doing some respondsToSelector tests, because on Tiger/Leopard
	// the API was undocumented.
	if ([panel respondsToSelector:@selector(showsHiddenFiles)] && [panel respondsToSelector:@selector(setShowsHiddenFiles:)]) {
		showHiddenFilesButton = [[NSButton alloc] init];
		[showHiddenFilesButton setButtonType:NSButtonTypeSwitch];

		CFStringRef hiddenFilesString = CFStringCreateWithCString(0, _("Show hidden files").encode().c_str(), kCFStringEncodingUTF8);
		[showHiddenFilesButton setTitle:(NSString*)hiddenFilesString];
		CFRelease(hiddenFilesString);

		[showHiddenFilesButton sizeToFit];
		if (ConfMan.getBool("gui_browser_show_hidden", Common::ConfigManager::kApplicationDomain)) {
			[showHiddenFilesButton setState:NSControlStateValueOn];
			[panel setShowsHiddenFiles: YES];
		} else {
			[showHiddenFilesButton setState:NSControlStateValueOff];
			[panel setShowsHiddenFiles: NO];
		}
		[panel setAccessoryView:showHiddenFilesButton];

		[showHiddenFilesButton setTarget:self];
		[showHiddenFilesButton setAction:@selector(showHiddenFiles:)];
	}

#if MAC_OS_X_VERSION_MAX_ALLOWED <= 1090
	if ([panel runModal] == NSOKButton) {
#else
	if ([panel runModal] == NSModalResponseOK) {
#endif
		NSURL *url = [panel URL];
		if ([url isFileURL]) {
			_url = url;
			[_url retain];
		}
	}

	[showHiddenFilesButton release];
	_panel = nil;
}

- (IBAction) showHiddenFiles : (id) sender {
	if ([sender state] == NSControlStateValueOn) {
		[_panel setShowsHiddenFiles: YES];
		ConfMan.setBool("gui_browser_show_hidden", true, Common::ConfigManager::kApplicationDomain);
	} else {
		[_panel setShowsHiddenFiles: NO];
		ConfMan.setBool("gui_browser_show_hidden", false, Common::ConfigManager::kApplicationDomain);
	}
}

@end

Common::DialogManager::DialogResult MacOSXDialogManager::showFileBrowser(const Common::U32String &title, Common::FSNode &choice, bool isDirBrowser) {
	DialogResult result = kDialogCancel;

	// Get current encoding
	CFStringEncoding stringEncoding = kCFStringEncodingUTF8;

	// Convert labels to NSString
	CFStringRef titleRef = CFStringCreateWithCString(0, title.encode().c_str(), stringEncoding);
	CFStringRef chooseRef = CFStringCreateWithCString(0, _("Choose").encode().c_str(), stringEncoding);

	beginDialog();

	// Temporarily show the real mouse
	CGDisplayShowCursor(kCGDirectMainDisplay);

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];

	BrowserDialogPresenter *presenter = [[BrowserDialogPresenter alloc] init];
	presenter->_isDirBrowser = isDirBrowser;
	presenter->_title = (CFStringRef)CFRetain(titleRef);
	presenter->_prompt = (CFStringRef)CFRetain(chooseRef);
	[presenter performSelectorOnMainThread:@selector(showOpenPanel) withObject:nil waitUntilDone:YES];
	if (presenter->_url) {
		Common::Path filename([[presenter->_url path] UTF8String]);
		choice = Common::FSNode(filename);
		result = kDialogOk;
	}
	[presenter release];

	[pool release];
	[keyWindow makeKeyAndOrderFront:nil];

	CFRelease(titleRef);
	CFRelease(chooseRef);

	endDialog();

	return result;
}

#endif
