/*
 * compat/libintl.h - identity gettext stubs for the Amix (SVR4.0)
 * cross build.  There is no message-catalog i18n on Amix; every
 * gettext-family call collapses to its untranslated argument.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_LIBINTL_H
#define AMIX_COMPAT_LIBINTL_H

#define gettext(msgid)			(msgid)
#define dgettext(domain, msgid)		(msgid)
#define dcgettext(domain, msgid, cat)	(msgid)
#define textdomain(domain)		((char *)0)
#define bindtextdomain(domain, dir)	((char *)0)

#endif /* AMIX_COMPAT_LIBINTL_H */
