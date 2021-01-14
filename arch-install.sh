#!/bin/sh

### symbolizes debug (change when you want the actual functionality)

# get defaults from -d flag
while getopts d: flags; do
	case $flags in
		d) PATH=$PATH:.; . "$OPTARG";; # need to add to path since /bin/sh doesn't read from current dir
		?) printf "Usage: %s [-d defaultfile]\n" $0; exit 1;;
	esac
done

# returns 0 if input is y or yes (case insensitive) and 1 otherwise
yes() {
	read yes_or_no
	case $(echo "$yes_or_no" | awk '{print tolower($0)}') in
		y|yes) 0;;
		*) 1;;
	esac
}

kbd_layout_list="$(find /usr/share/kbd/keymaps -name '*.map.gz' | awk -F '/' '{print substr($NF, 1, length($NF)-length(".map.gz"))}' | sort)"
if [ "$keyboard_layout" ]; then
	printf '[DEFAULT] '
	if echo "$kbd_layout_list" | grep -Fx "$keyboard_layout" >/dev/null; then
		echo "Keyboard layout set to $keyboard_layout"
		loadkeys $keyboard_layout
	else
		echo "[WARNING] Keyboard layout $keyboard_layout not found; defaulting to us"
	fi
else
	while true; do
		printf 'Enter keyboard layout to use (default is US QWERTY, ? for list of options): '
		read keyboard_layout
		case "$keyboard_layout" in
			?) echo "$kbd_layout_list" | less;;
			"") echo Keeping default US QWERTY layout; break;;
			*)
				if echo "$kbd_layout_list" | grep -Fx "$keyboard_layout" >/dev/null; then
					echo loadkeys "$keyboard_layout"
					break
				else
					echo "Layout $keyboard_layout not found"
				fi
		esac
	done
fi
