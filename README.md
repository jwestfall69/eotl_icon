# eotl_icon

This is a TF2 sourcemod plugin.

This plugin will put an icon/sprite above vip players that are alive when a round ends.  Its based off the [donator recognition](https://forums.alliedmods.net/showthread.php?p=1128547) plugin.

It has the following differences from the origin plugin

  * Rewritten in new style sourcepawn syntax
  * Adds config file to support numerous different icons
  * Allows each VIP to have their own icon defined (in the database)
  * Removed some unneeded features


### Dependencies
<hr>

**Database**<br>

This plugin is expecting the following to exist (hardcoded as its what we need)

* Database config named 'default'
* Table on that database named 'vip_users'
* Columns in that table named 'streamID' and 'iconID'

This information provides the plugin with a list of VIP's and their associated icon.

### Config File (addons/sourcemod/configs/eotl_icon.cfg)
<hr>

This config file defines the different possible icons that a VIP could have.  Please refer to the config file for more detail on this.

### ConVars
<hr>

**eotl_icon_debug [0/1]**

Disable/Enable debug logging

Default: 0 (disabled)