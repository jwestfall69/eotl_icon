# eotl_icon

This is a TF2 sourcemod plugin I wrote for the [EOTL](https://www.endofthelinegaming.com/) community.

This plugin will put an icon/sprite above vip players that are alive when a round ends.  Its based off the [donator recognition](https://forums.alliedmods.net/showthread.php?p=1128547) plugin.

It has the following differences from the origin plugin

  * Rewritten in new style sourcemod syntax
  * Adds config file to support numerous different icons
  * Allows each VIP to have their own icon defined (in the database)
  * Allow executing commands for an icon when its enabled/disabled
  * Removed some unneeded features

### Dependencies
<hr>

This plugin depends on eotl_vip_core plugin.

### Config File (addons/sourcemod/configs/eotl_icon.cfg)
<hr>

This config file defines the different possible icons that a VIP could have.  Please refer to the config file for more detail on this.

### ConVars
<hr>

**eotl_icon_debug [0/1]**

Disable/Enable debug logging

Default: 0 (disabled)