# This Makefile fragment (since dpkg 1.22.0) handles the build API.

# Default API level when not set.
DPKG_BUILD_API ?= $(shell dpkg-buildapi)

# We could use only built-in GNU make functions, but that seems too much
# complexity given no integer operators, given that we currently have to
# fetch the build API level anyway.
dpkg_build_api_ge = $(shell test "$(DPKG_BUILD_API)" -ge "$(1)" && echo yes)
