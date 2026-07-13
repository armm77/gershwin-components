include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Build

Build_OBJC_FILES = \
	main.m \
	BuildController.m \
	BuildApplication.m \
	CatalogEntry.m \
	CatalogController.m

Build_HEADERS = \
	BuildController.h \
	BuildApplication.h \
	CatalogEntry.h \
	CatalogController.h

ADDITIONAL_GUI_LIBS += -ldispatch

Build_APPLICATION_ICON = Build.png

Build_RESOURCE_FILES = \
	Resources/check.png \
	Resources/Blacklist.plist \
	Resources/GNUstep.info.plist \
	Resources/Catalog/Clock.plist \
	Resources/Catalog/Calculate.plist \
	Resources/Catalog/Weather.plist \
	Resources/Catalog/StepDown.plist \
	Info-gnustep.plist

include $(GNUSTEP_MAKEFILES)/application.make