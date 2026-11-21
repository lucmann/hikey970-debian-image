# Make sure /usr/sbin and /sbin are in PATH for all login users.
# /etc/profile resets PATH for non-root users before sourcing
# /etc/profile.d/*.sh, so PAM-only configuration (/etc/environment)
# is not enough for interactive login shells.

case ":${PATH}:" in
    *:/usr/sbin:*) ;;
    *) PATH="${PATH}:/usr/sbin" ;;
esac

case ":${PATH}:" in
    *:/sbin:*) ;;
    *) PATH="${PATH}:/sbin" ;;
esac

export PATH
