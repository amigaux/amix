/*
 * mp_desktop_nox.C -- ToolTalk's _Tt_desktop for the build host's
 * tt_type_comp, in place of lib/tt/lib/mp/mp_desktop.C, which needs Xlib.
 * tt_type_comp never opens a desktop session, but the session code linked
 * with it names the class; here every operation fails, as with no display.
 * The installed ToolTalk is built from mp_desktop.C as upstream has it.
 * MIT licence, see LICENSE in userland/packages.
 */
#include "tt_options.h"
#include <mp/mp_desktop.h>

sigjmp_buf _Tt_desktop::io_exception;

_Tt_desktop::_Tt_desktop() { priv = 0; user_io_handler = 0; }
_Tt_desktop::~_Tt_desktop() {}
int _Tt_desktop::init(_Tt_string, _Tt_dt_type) { return 0; }
int _Tt_desktop::io_error_proc(void *) { return 0; }
void _Tt_desktop::set_error_handler(_Tt_dt_errfn) {}
void _Tt_desktop::restore_user_handler() {}
int _Tt_desktop::close() { return 0; }
int _Tt_desktop::notify_fd() { return -1; }
int _Tt_desktop::process_event() { return 0; }
int _Tt_desktop::lock() { return 1; }
int _Tt_desktop::unlock() { return 1; }
int _Tt_desktop::set_prop(_Tt_string, _Tt_string &) { return 0; }
int _Tt_desktop::del_prop(_Tt_string) { return 0; }
int _Tt_desktop::get_prop(_Tt_string, _Tt_string &) { return 0; }
_Tt_string _Tt_desktop::session_name(_Tt_string) { return (char *)0; }

_Tt_desktop_lock::_Tt_desktop_lock() {}
_Tt_desktop_lock::_Tt_desktop_lock(const _Tt_desktop_ptr &dt) { _dt = dt; }
_Tt_desktop_lock::~_Tt_desktop_lock() {}
