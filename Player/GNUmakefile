#
# GNUmakefile for Player (Video & Audio Player)
#
ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

APP_NAME = Player
PACKAGE_NAME = Player
Player_PRINCIPAL_CLASS = NSApplication
Player_APPLICATION_ICON = Player.png

#
# Resource files
#
Player_RESOURCE_FILES = \
	Resources/Player.png \
	Resources/Info.plist \
	Resources/Info-gnustep.plist

Player_LOCALIZED_RESOURCE_FILES = \
	Localizable.strings

Player_LANGUAGES = English

# Build-time generation of Info files
Resources/Info.plist: Info.plist | Resources
	$(ECHO_NOTHING)if [ -n "$(INSTALL_FILE)" ]; then $(INSTALL_FILE) $< $@; else cp $< $@; fi$(END_ECHO)

Resources/Info-gnustep.plist: Resources/Info.plist
	$(ECHO_NOTHING)if command -v plmerge >/dev/null 2>&1; then \
	  plmerge $< "$(GNUSTEP_PLIST_DEPEND)" > $@; \
	else \
	  cp $< $@; \
	fi$(END_ECHO)

#
# Source files
#
Player_HEADER_FILES = \
	PlayerController.h

Player_OBJC_FILES = \
	PlayerController.m

Player_OBJC_FILES += Player_main.m

#
# AVFoundation framework - referenced from libs-av build tree
#
# Link with AVFoundation framework (installed system-wide via libs-av)
Player_GUI_LIBS += -lAVFoundation

#
# ItemFlow framework for album-art carousel
#
# On local builds ItemFlow is usually installed system-wide so -lItemFlow
# is found via default search paths.  On CI, ItemFlow is built in-tree but
# not yet installed — add a -L fallback so the linker finds it either way.
#
ITEMFLOW_SRC := $(CURDIR)/../ItemFlow
ITEMFLOW_LIB := $(ITEMFLOW_SRC)/ItemFlow.framework/Versions/Current
ADDITIONAL_INCLUDE_DIRS += -I$(ITEMFLOW_SRC)
ADDITIONAL_LDFLAGS += -L$(ITEMFLOW_LIB)
ADDITIONAL_GUI_LIBS += -lItemFlow -lGL -lGLU
# ItemFlow uses libdispatch internally; on FreeBSD the strict linker needs it explicitly.
ADDITIONAL_GUI_LIBS += -ldispatch

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/application.make

# Override desktop file creation — we don't need .desktop files for Gershwin.
$(APP_DIR)/Resources/$(GNUSTEP_INSTANCE).desktop:
	$(ECHO_NOTHING)echo "Desktop file generation disabled" > /dev/null$(END_ECHO)
	$(ECHO_NOTHING)touch $(APP_DIR)/Resources/$(GNUSTEP_INSTANCE).desktop; chmod a+x $(APP_DIR)/Resources/$(GNUSTEP_INSTANCE).desktop$(END_ECHO)

# Ensure Info.plist is copied into the built app and Info-gnustep is generated from it
all:: copy-info

copy-info: $(APP_NAME).app
	$(ECHO_NOTHING)if [ -n "$(INSTALL_FILE)" ]; then $(INSTALL_FILE) Info.plist $(APP_NAME).app/Resources/Info.plist; else cp Info.plist $(APP_NAME).app/Resources/Info.plist; fi$(END_ECHO)
	$(ECHO_NOTHING)if command -v plmerge >/dev/null 2>&1; then \
	  plmerge $(APP_NAME).app/Resources/Info-gnustep.plist Info.plist "$(GNUSTEP_PLIST_DEPEND)"; \
	fi$(END_ECHO)

-include GNUmakefile.postamble
