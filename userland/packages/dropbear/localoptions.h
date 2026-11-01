/*
 * localoptions.h -- Dropbear's compile-time options for Amix.
 *
 * Read by the build in place of upstream's defaults where it sets a value
 * (src/default_options.h documents every option).  The algorithm set is the
 * one README.md measures: what is not offered is not compiled in.
 * MIT, this repository.
 */
#ifndef AMIX_DROPBEAR_LOCALOPTIONS_H
#define AMIX_DROPBEAR_LOCALOPTIONS_H

/* --- paths: every name within s5's 14 bytes ------------------------------ */
#define DSS_PRIV_FILENAME "/etc/dropbear/host_dss"
#define RSA_PRIV_FILENAME "/etc/dropbear/host_rsa"
#define ECDSA_PRIV_FILENAME "/etc/dropbear/host_ecdsa"
#define ED25519_PRIV_FILENAME "/etc/dropbear/host_ed25519"
#define DROPBEAR_PIDFILE "/etc/dropbear/dropbear.pid"
#define DROPBEAR_PATH_SSH_PROGRAM "/opt/amix/bin/dbclient"
#define SFTPSERVER_PATH "/opt/amix/libexec/sftp-server"
#define DEFAULT_PATH "/opt/amix/bin:/usr/bin:/usr/ucb"
#define DEFAULT_ROOT_PATH "/opt/amix/bin:/usr/sbin:/usr/bin:/sbin:/etc"

/* --- key exchange: curve25519 and its post-quantum hybrid ---------------- */
#define DROPBEAR_CURVE25519 1
#define DROPBEAR_MLKEM768 1
#define DROPBEAR_SNTRUP761 0
#define DROPBEAR_ECDH 0
#define DROPBEAR_DH_GROUP1 0
#define DROPBEAR_DH_GROUP14_SHA1 0
#define DROPBEAR_DH_GROUP14_SHA256 0
#define DROPBEAR_DH_GROUP16 0

/* --- host and user keys: ed25519; RSA (rsa-sha2-256) for compatibility --- */
#define DROPBEAR_ED25519 1
#define DROPBEAR_RSA 1
#define DROPBEAR_RSA_SHA1 0
#define DROPBEAR_DSS 0
#define DROPBEAR_ECDSA 0
#define DROPBEAR_SK_KEYS 0
#define DROPBEAR_DEFAULT_RSA_SIZE 3072

/* --- ciphers and MACs ----------------------------------------------------- */
#define DROPBEAR_CHACHA20POLY1305 1
#define DROPBEAR_AES128 1
#define DROPBEAR_AES256 0
#define DROPBEAR_3DES 0
#define DROPBEAR_ENABLE_CTR_MODE 1
#define DROPBEAR_ENABLE_CBC_MODE 0
#define DROPBEAR_ENABLE_GCM_MODE 0
#define DROPBEAR_SHA2_256_HMAC 1
#define DROPBEAR_SHA2_512_HMAC 0
#define DROPBEAR_SHA1_HMAC 0
#define DROPBEAR_SHA1_96_HMAC 0

/* --- the server's user switch ----------------------------------------------
 * Upstream drops to the user right after authentication and keeps a saved
 * utmp group for the login records.  SVR4.0 cannot set a saved group ID
 * by itself and writes utmpx only for root, so the server switches user
 * when it starts the session's shell or command, the way Dropbear did
 * before 2026.89. */
#define DROPBEAR_SVR_DROP_PRIVS 0

/* --- features ------------------------------------------------------------- */
#define DROPBEAR_X11FWD 0
#define DROPBEAR_SVR_AGENTFWD 0
#define DROPBEAR_CLI_AGENTFWD 0
#define DROPBEAR_SVR_LOCALSTREAMFWD 0
#define DROPBEAR_SVR_REMOTESTREAMFWD 0
#define DROPBEAR_SVR_PAM_AUTH 0
#define DROPBEAR_USE_PRNGD 0
#define DROPBEAR_CLI_ASKPASS_HELPER 0
#define DO_HOST_LOOKUP 0

#endif
