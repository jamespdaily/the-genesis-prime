# Items and vendors

- **I (`0x17`) opens the bag.** A slot at row `r` and column `c` (from 0) sits at about `(2676 + 78c, 1392 + 78r)` in screen pixels, while the bag is in its default place.
- **The playtest tool has no right-click, drag or wheel.** Send them with `playtest do`, defining a small type once per helper session:

  ```powershell
  if (-not ("EldanMouse" -as [type])) { Add-Type -TypeDefinition @"
  using System; using System.Runtime.InteropServices;
  public static class EldanMouse {
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, int d, UIntPtr e);
    static void Wait(int ms) { System.Threading.Thread.Sleep(ms); }
    public static void Right(int x, int y) { SetCursorPos(x, y); Wait(120); mouse_event(8,0,0,0,UIntPtr.Zero); Wait(200); mouse_event(16,0,0,0,UIntPtr.Zero); }
    public static void Drag(int x1, int y1, int x2, int y2) { SetCursorPos(x1, y1); Wait(120); mouse_event(2,0,0,0,UIntPtr.Zero); Wait(150); for (int i = 1; i <= 12; i++) { SetCursorPos(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12); Wait(30); } Wait(150); mouse_event(4,0,0,0,UIntPtr.Zero); }
    public static void Wheel(int x, int y, int notches) { SetCursorPos(x, y); for (int i = 0; i < Math.Abs(notches); i++) { mouse_event(0x800,0,0,notches < 0 ? -120 : 120,UIntPtr.Zero); Wait(60); } }
  }
  "@ }
  [EldanScreen]::Front() | Out-Null
  [EldanMouse]::Right(2676, 1392)
  ```
- **A right-click on a bag item equips it, sells it while a vendor is open, or uses it.** Close the vendor first to use an item.
- **Shift-click a stack to split it.** Hold Shift (`playtest down 0x2A`), click the stack, release, click Split in the dialog, then click an empty slot.
- **To delete, drag the item out of the bag and hold Delete.** The confirmation's Delete button ignores `playtest click`'s 60 ms press; a drag from and to the button, which holds it about 150 ms, registers. Wait for the dialog before pressing.
- **Vendor stock is written by hand.** The world data has none. Insert `world.vendor`, `world.vendor_category` and `world.vendor_item` rows in `genesis_prime_dev` for a merchant's spawn id, then restart the server: a map loads its vendors once. Pick the merchant by its Creature2 description: "Vendor" but not "Taxi". Taxi kiosk 59861 is a flight master, and the client opens its flight window by itself. Seller Frota, spawn 59946 ("Feralplain General Goods"), stands at (-5052.6, -946.7, -1507.3); enter at (-5058, -946.7, -1510) and turn right to face it, then right-click it. Its stock in `genesis_prime_dev` is 4833, 175 and 987. Item 4833 is deprecated, so never test with it. Sell-test with 175 (Tuft of Dagun Fur, 9c, sells for 1c): the client refuses to sell 987 (Parched Bingberry, Item2 flag 4) with "Item cannot be sold" and sends the server nothing.
- **Never stock or test with a deprecated item**, Item2 flag 0x4000. The client rebuilds it from a placeholder with no spell, so it can never be used. Usable test items: 7063 (Brutality Stimulant, cast on the player) and 6915 (a stimpack, which the client refuses at full health).
- **A use or cast failure shows only as a floater over the player, for about 1.3 s, never in chat.** Screenshot within 0.3 s, from the same `playtest do` script: `[EldanMouse]::Right(x, y); Start-Sleep -Milliseconds 150; [EldanScreen]::Shot("C:\eldan-playtest\use.jpg")`. Then copy it with `scp dada@192.168.8.157:C:/eldan-playtest/use.jpg tmp/playtest/`.
- **After a teleport the camera can sit inside the scenery**, with the player out of view and the wheel doing nothing. Walk a step (`playtest key 0x11 1000`) to free it.
- **`!item add <id> [count] [charges]` and `!character xp <amount>` set up a test** without fighting or buying.
- **`!item add` can leave a stack the client will not use.** `!item add 7063 2` beside a held stack of 2 topped it up to 3 and put the rest in a new stack with 0 charges; a right-click on that stack sent nothing and showed no floater. Check `character.item`'s `charges` before blaming the server.
- **To test cancelling a buff, use 7063 (Brutality Stimulant).** Its spell 25136 gives the player a 60 s modifier, shown as an icon above the health bar at about (1029, 1608). A right-click on the icon sends `ClientCancelEffect`, and the icon goes within 0.7 s.
- **To test an item with a prerequisite, use 49973** (Velocirex (Provisionary) License). Its prerequisite holds for a character that lacks spell 77357, and its spell casts here: the item is used up and the player glows blue. 4101 (Grinder) is used up but its spell is refused, because effect type 125 is not ported, so the item is lost. 92112 (Snowball Launcher) is refused for its spell's caster prerequisite.
- **The client blocks an item whose prerequisite it knows fails** and sends nothing. The item shows a ⊘ icon, and a red X when right-clicked. 12402 (Yockum Bingberry Tonic, level above 20) is one.
- **After a failed use, the client can mark the next item clicked with a red X and send nothing.** Log in again before suspecting the server, and use the item under test first.
