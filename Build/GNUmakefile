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
	Resources/check.png

include $(GNUSTEP_MAKEFILES)/application.make

after-$(APP_NAME)-all::
	sed -i 's/; }$$/; CFBundleDocumentTypes = ( { CFBundleTypeName = Makefile; CFBundleTypeRole = Editor; CFBundleTypeExtensions = (Makefile, makefile, GNUmakefile, GNUmakefile.in); }, ); }/' $(APP_NAME).app/Resources/Info-gnustep.plist