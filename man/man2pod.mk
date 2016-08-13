.NOTPARALLEL:

all: convert check unfuzz update-po update-git

convert:
	for m in *.man; do perl man2pod.pl <$$m | perl podfixup.pl \
	  | cat -s >$${m%%.man}.pod; done

unfuzz:
	for p in po/*.po; do \
	  perl pod-po-unfuzz.pl <$$p >$$p.new; \
	  mv $$p.new $$p; \
	done

check:
	for p in *.pod; do pod2man $$p >/dev/null; done

update-po:
	$(MAKE) update-po

update-git:
	git rm *.man
	git add *.pod
	git add po/
