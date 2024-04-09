include $(srcdir)/mk/buildtools.mk

tools := \
  AR \
  AS \
  CC \
  CXX \
  F77 \
  FC \
  LD \
  NM \
  OBJC \
  OBJCOPY \
  OBJCXX \
  OBJDUMP \
  PKG_CONFIG \
  RANLIB \
  STRIP \
  # EOL
loop_targets := $(tools) $(tools:=_FOR_BUILD)

test: $(loop_targets)

$(loop_targets):
	test "$($@)" = "$(TEST_$@)"
