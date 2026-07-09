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
	awk '{gsub(/; }$$/, "; NSTypes = ( { CFBundleTypeName = Makefile; CFBundleTypeRole = Editor; NSUnixExtensions = (GNUmakefile, \"GNUmakefile.in\", Makefile, makefile); }, ); }"); print}' \
	  $(APP_NAME).app/Resources/Info-gnustep.plist > $(APP_NAME).app/Resources/Info-gnustep.plist.tmp && \
	  mv $(APP_NAME).app/Resources/Info-gnustep.plist.tmp $(APP_NAME).app/Resources/Info-gnustep.plist