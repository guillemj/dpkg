#!/bin/sh

xgettext --default-domain=dpkg --directory=.. \
	 --add-comments --keyword=_ --keyword=N_ \
	 --files-from=POTFILES.in && test ! -f dpkg.po \
	 || ( rm -f dpkg.pot && mv dpkg.po dpkg.pot )

catalogs='en.gmo fr.gmo es.gmo ja_JP.ujis.gmo'
for cat in $catalogs; do
  lang=`echo $cat | sed 's/\.gmo$//'`
  mv $lang.po $lang.old.po
  echo "$lang:"
  if msgmerge $lang.old.po dpkg.pot -o $lang.po; then
    rm -f $lang.old.po
  else
    echo "msgmerge for $cat failed!"
    rm -f $lang.po
    mv $lang.old.po $lang.po
  fi
done
