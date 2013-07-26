
# UNIT_NAME is the Vala namespace.  A file named UNIT_NAME.vala must be in this directory with
# a init() and terminate() function declared in the namespace.
UNIT_NAME := Folders

# UNIT_DIR should match the subdirectory the files are located in.  Generally UNIT_NAME in all
# lowercase.  The name of this file should be UNIT_DIR.mk.
UNIT_DIR := folders

# All Vala files in the unit should be listed here with no subdirectory prefix.
#
# NOTE: Do *not* include the unit's master file, i.e. UNIT_NAME.vala.
UNIT_FILES := \
	Branch.vala \
	Page.vala

# Any unit this unit relies upon (and should be initialized before it's initialized) should
# be listed here using its Vala namespace.
#
# NOTE: All units are assumed to rely upon the unit-unit.  Do not include that here.
UNIT_USES := \
	Sidebar \
	Photos

# List any additional files that are used in the build process as a part of this unit that should
# be packaged in the tarball.  File names should be relative to the unit's home directory.
UNIT_RC :=

# unitize.mk must be called at the end of each UNIT_DIR.mk file.
include unitize.mk

