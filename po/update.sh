#!/bin/sh

xgettext --default-domain=dpkg --directory=.. \
	 --add-comments --keyword=_ --keyword=N_ \
	 --files-from=POTFILES.in && test ! -f dpkg.po \
	 || ( rm -f dpkg.pot && mv dpkg.po dpkg.pot )

# Moving along..

catalogs=`ls *.po`
for cat in $catalogs; do
  if [ "$cat" = "dpkg.po" ] ; then continue ; fi
  lang=`echo $cat | sed 's/\.po$//'`
  mv $cat $lang.old.po
  echo "$lang:"
  if msgmerge $lang.old.po dpkg.pot -o $cat; then
    rm -f $lang.old.po
  else
    echo "msgmerge for $cat failed!"
    if cmp --quiet $cat $lang.old.po ; then
      rm -f $lang.old.po
    else
      mv -f $lang.old.po $cat
    fi
  fi
done
