include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Build

Build_OBJC_FILES = \
	main.m \
	BuildController.m \
	BuildApplication.m

Build_HEADERS = \
	BuildController.h \
	BuildApplication.h

ADDITIONAL_GUI_LIBS += -ldispatch

Build_APPLICATION_ICON = Build.png

Build_RESOURCE_FILES = \
	Resources/check.png \
	Resources/Blacklist.plist \
	Info-gnustep.plist

include $(GNUSTEP_MAKEFILES)/application.make