# Mail

- **Enter beside mailbox spawn 59818** (creature 10906) in Feralplain Collective, world 22. The development character's saved place is at (-5052.17, -945.34, -1550.46), 3.3 units from it.
- **Right-click the mailbox to open the mail window.** The client sends `ClientEntityInteract` type 0x44 and opens the window itself.
- **The client allows items, credits and cash on delivery only within 20 m of any mailbox**, with no click (`MailSystemLib.AtMailbox`, GameFormula 237). The server checks the mailbox the message names at each action.
- **To attach an item, click Begin New Mail, then drag the item from the bag onto the first attachment slot.** Use 175 (Tuft of Dagun Fur). A red X on the dragged item means the client refuses it. Chest armour 90206 carries the client's own ⊘ mark and is refused for another reason.
