This is a 'pivot' UI for DF Hack for Dwarf Fortress

Installation is a bit wonky, as I'm not currently adding it as a 'addon'. I've essentially reimplemented the trade UI.

# Installation

* BACKUP YOUR ORIGINAL CARAVAN FOLDER (found in <Dwarf Fortress>\hack\scripts\internal\caravan)
* BACKUP YOUR ORIGINAL caravan.lua (found in <Dwarf Fortress>\hack\caravan.lua)
* Download this source as a .zip file
* Extract it into <Dwarf Fortress>\hack\scripts\internal\caravan
* Edit your new caravan.lua and add
 * this line to the top (or close to the top): `local pivottrade = reqscript('internal/caravan/pivottrade')`
 * this line to the OVERLAY_WIDGETS object `pivottradebanner=pivottrade.TradeBannerOverlay,`
