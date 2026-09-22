/* The Chikoria codex: every creature, avatar and mount the homepage can open.
   One world, one telling. Elements and classes match the game's own tables
   (Fire, Water, Light, Storm, Beast; normal, legendary), and every legend is
   set in the places the Realm actually has: the Chikoria River, the Crystal
   Cave, the Wicked Temple and Grimwick, and the Chikiseum. */
window.CHIKORIA_CODEX = {
  world: {
    name: "Chikoria",
    intro:
      "Chikoria is a ring of islands lifted out of the sea by the Chiki crystals that grow in its bedrock. " +
      "Five hearths feed the world: the Ember Ridge, the Tide, the Dawn Spire, the Storm Peaks and the Wildwood. " +
      "Every Chikimon carries one hearth in its heart. The Chikoria River runs from the Crystal Cave to the coast, " +
      "the Wicked Temple broods where Grimwick the Wicked Warlock turned the old shrine against the world, and the " +
      "Chikiseum is where trainers and their companions settle who is strongest.",
  },
  chikimon: {
    firix: {
      name: "Firix", element: "Fire", cls: "normal", title: "The First Spark",
      home: "Ember Ridge foothills",
      art: "/site-assets/dex-firix.webp", model: "/site-assets/models/firix.glb",
      legend: [
        "Every trainer's story in Chikoria seems to start with a Firix. They are born in the warm cinder-fields below the Ember Ridge, where the ground never fully cools, and they leave the nest the moment their tail catches its first flame.",
        "A Firix is small, quick and completely fearless. It will square up to a Tyrannos without a second thought, which is why the old trainers say a Firix does not learn courage from you; you learn it from the Firix.",
      ],
    },
    dragonos: {
      name: "Dragonos", element: "Fire", cls: "legendary", title: "Warden of the Ember Ridge",
      home: "Ember Ridge summit",
      art: "/site-assets/dex-dragonos.webp", model: "/site-assets/models/dragonos.glb",
      legend: [
        "The Ember Ridge is the highest ground in Chikoria, and Dragonos holds its summit. The ridge's heat is his to keep: when the fires of the world burn low, he flies the length of the ridge and breathes them back to life.",
        "Dragonos is proud, and rightly so, but he is not cruel. He answers only trainers who have already proven themselves in the Chikiseum, and once he has chosen someone he never chooses again.",
      ],
    },
    galador: {
      name: "Galador", element: "Water", cls: "legendary", title: "Guardian of the River",
      home: "Chikoria River headwaters",
      art: "/site-assets/dex-galador.webp", model: "/site-assets/models/galador.glb",
      legend: [
        "Galador is the river itself given a body. He was born where the Chikoria River leaves the Crystal Cave, and its water still runs cooler and clearer wherever he swims.",
        "When Grimwick first tried to poison the river from the Wicked Temple, it was Galador who turned the current back. He has guarded the headwaters ever since, and a trainer who earns his trust will never lack for clean water, safe crossings or a fast way downstream.",
      ],
    },
    astraya: {
      name: "Astraya", element: "Light", cls: "legendary", title: "The Wishing Star",
      home: "Dawn Spire, the night sky",
      art: "/site-assets/dex-astraya.webp", model: "/site-assets/models/astraya.glb",
      legend: [
        "On clear nights over the Dawn Spire a single star falls and never lands. That is Astraya, a cat of pure starlight whose tail draws the comet-line the fishers of Chikoria steer by.",
        "Astraya is playful and impossible to catch, and she chooses her trainer rather than the other way around. Those she picks say she found them on the night they made a wish they did not think anyone heard.",
      ],
    },
    bamboran: {
      name: "Bamboran", element: "Beast", cls: "legendary", title: "Keeper of the Wildwood Gate",
      home: "The Wildwood",
      art: "/site-assets/dex-bamboran.webp", model: "/site-assets/models/bamboran.glb",
      legend: [
        "Bamboran guards the bamboo gate where the Wildwood meets the river path. He wears the green-and-gold armour of the old forest wardens, and the jade medallion at his chest is said to be the first Chiki crystal ever cut.",
        "He is slow to anger and slower to move, but when the Wildwood is threatened the whole forest moves with him. Trainers who help him tend the groves are allowed to gather there, which is where the sweetest berries in Chikoria grow.",
      ],
    },
    borealon: {
      name: "Borealon", element: "Water", cls: "legendary", title: "The Frozen Tide",
      home: "The northern ice shelf",
      art: "/site-assets/dex-borealon.webp", model: "/site-assets/models/borealon.glb",
      legend: [
        "Where the Tide freezes at the northern edge of Chikoria, Borealon walks the ice. The crystals along his back are frozen seawater grown over centuries, and he can call a blizzard across the whole coast with one shake of his coat.",
        "Borealon is patient and quiet. He keeps the winter in its place, holding it back from the river valley, and he only leaves the ice when the Wicked Temple's corruption spreads far enough north to reach him.",
      ],
    },
    solvarex: {
      name: "Solvarex", element: "Fire", cls: "legendary", title: "The Noon Lion",
      home: "Ember Ridge, the sun terraces",
      art: "/site-assets/dex-solvarex.webp", model: "/site-assets/models/solvarex.glb",
      legend: [
        "Solvarex carries the noon sun on his brow. His mane is living flame and the sun-crest on his forehead brightens as the day climbs, so that at midday he is hard to look at directly.",
        "He is the champion of the Chikiseum's oldest bouts and the only Chikimon Dragonos calls an equal. Solvarex prefers a fair fight to an easy one and will refuse a victory he has not earned.",
      ],
    },
    crysalune: {
      name: "Crysalune", element: "Water", cls: "legendary", title: "The Moon Moth",
      home: "The Crystal Cave",
      art: "/site-assets/dex-crysalune.webp", model: "/site-assets/models/crysalune.glb",
      legend: [
        "Deep in the Crystal Cave, where the Chikoria River is born, Crysalune sleeps through the day on the largest crystal in Chikoria. At night she rises through the cave mouth and her wings scatter moonlight across the water.",
        "Her wings are frost, not scale, and the crescent moons on them mark the tides. Fishers wait for her to pass before they cast, because the fish follow her light.",
      ],
    },
    vesperos: {
      name: "Vesperos", element: "Light", cls: "legendary", title: "The Evening Watch",
      home: "Above the Wicked Temple",
      art: "/site-assets/dex-vesperos.webp", model: "/site-assets/models/vesperos.glb",
      legend: [
        "Vesperos is light that chose the dark. A great violet bat crowned with a crescent, he holds the last light of evening and carries it through the night so that morning has somewhere to start from.",
        "He circles the Wicked Temple every night, watching Grimwick's corruption so it cannot spread unseen. Many mistake him for one of the Warlock's creatures. He is the opposite, and he does not mind the mistake.",
      ],
    },
    adalor: {
      name: "Adalor", element: "Light", cls: "legendary", title: "The Dawn Herald",
      home: "The Dawn Spire",
      art: "/site-assets/dex-adalor.webp", model: "/site-assets/models/adalor.glb",
      legend: [
        "Adalor lives at the tip of the Dawn Spire, the tallest of Chikoria's floating isles, and every sunrise in the world begins when he opens his wings. The crystal at his crown is the same blue as the sky he brings.",
        "His Holy Smite is the light that cleanses corruption, which makes him the Wicked Temple's oldest enemy. Trainers who reach the Spire find him waiting; he has already seen them coming.",
      ],
    },
    tyrannos: {
      name: "Tyrannos", element: "Beast", cls: "legendary", title: "King of the Wildwood",
      home: "The deep Wildwood",
      art: "/site-assets/dex-tyrannos.webp", model: "/site-assets/models/tyrannos.glb",
      legend: [
        "Tyrannos is the oldest living thing in the Wildwood. The crystals along his spine grew into him over a lifetime longer than anyone has counted, and the ground still shakes a little when he decides to walk.",
        "He is loud, hungry and enormously good-natured with those he likes. In the Chikiseum he is a wall that bites, and trainers who bring him learn quickly that he does not know how to hold back.",
      ],
    },
    grovador: {
      name: "Grovador", element: "Storm", cls: "legendary", title: "The Thunder Grove",
      home: "Storm Peaks, the lightning groves",
      art: "/site-assets/dex-grovador.webp", model: "/site-assets/models/grovador.glb",
      legend: [
        "High on the Storm Peaks there is a grove where the trees are struck so often they have turned to violet crystal. Grovador was born there, and the crystal grew into his mane and tail as it grew into the trees.",
        "He carries the storm with him. Clouds gather where he rests, and when he charges the air cracks. For all that, he is gentle with small creatures and is often seen letting a Firix nap between his paws.",
      ],
    },
    horoxyn: {
      name: "Horoxyn", element: "Storm", cls: "legendary", title: "Keeper of the Hours",
      home: "Storm Peaks observatory",
      art: "/site-assets/dex-horoxyn.webp", model: "/site-assets/models/horoxyn.glb",
      legend: [
        "Horoxyn keeps time for Chikoria. The gold rings around his body are clockwork that ticks with the storms, and it is said the seasons would drift if he ever stopped counting.",
        "He is the wisest of the Storm Chikimons and the least talkative. When Grimwick took the Wicked Temple, Horoxyn was the one who saw the shape of what was coming, and he has been arranging the pieces against it ever since.",
      ],
    },
    rivaros: {
      name: "Rivaros", element: "Water", cls: "legendary", title: "Warden of the Gathering Banks",
      home: "The Chikoria River, lower banks",
      art: "/site-assets/dex-rivaros.webp", model: "/site-assets/models/rivaros.glb",
      legend: [
        "Rivaros patrols the wide, slow part of the Chikoria River where trainers come to gather and fish. His copper armour was hammered from the river's own ore, and the water gem at his shoulder rises and falls with the tide.",
        "He is steady, stubborn and impossible to knock over. Rivaros will let anyone fish his banks, but he watches carefully, and nothing taken from the river ever goes to waste.",
      ],
    },
    astragor: {
      name: "Astragor", element: "Beast", cls: "legendary", title: "The Night Titan",
      home: "The Wildwood, the deep caves",
      art: "/site-assets/dex-astragor.webp", model: "/site-assets/models/astragor.glb",
      legend: [
        "Astragor is the strength of the Wildwood, a titan the colour of the night sky with a violet Chiki crystal set in his chest. His roar rallies every Beast Chikimon within earshot.",
        "He was the first to answer when Grimwick's corrupted Chikimons poured out of the Wicked Temple, and he held the temple road alone until the others arrived. Trainers who earn his loyalty gain a bodyguard who never sleeps.",
      ],
    },
  },
  avatar: {
    Knight: {
      name: "The Knight", art: "/nft/avatar/Knight.png", kicker: "Avatar / Royal guard",
      legend: [
        "The castle at the heart of Chikoria still keeps a guard, and the Knight is its youngest. The crown-blue cloak marks a trainer sworn to the river valley: first to the Wicked Temple's gates, last to leave them.",
      ],
    },
    Mystic: {
      name: "The Mystic", art: "/nft/avatar/Mystic.png", kicker: "Avatar / Crystal scholar",
      legend: [
        "The Mystic reads the Chiki crystals. Trained in the Crystal Cave beneath Crysalune's sleeping place, they carry a staff cut from the cave and are the trainers most likely to know what Grimwick will try next.",
      ],
    },
    Navigator: {
      name: "The Navigator", art: "/nft/avatar/Navigator.png", kicker: "Avatar / Island charter",
      legend: [
        "Chikoria's islands drift, a little, every year. The Navigator keeps the charts, following Astraya's comet-line at night and the river by day. No trainer has seen more of the world.",
      ],
    },
    Star: {
      name: "The Star", art: "/nft/avatar/Star.png", kicker: "Avatar / Chikiseum favourite",
      legend: [
        "The Chikiseum has its champions and it has its darling. The Star fights in pink and heart-light, sings before every bout, and has never once lost the crowd, even on the nights the match went the other way.",
      ],
    },
    chemist: {
      name: "The Chemist", art: "/nft/avatar/chemist.png", kicker: "Avatar / Ember alchemist",
      legend: [
        "Goggles down, the Chemist works with what the Ember Ridge gives up: cinders, sulphur and crystal dust. Their brews power half the ability cards used in the temple, and a few of the explosions.",
      ],
    },
    classic: {
      name: "The Classic", art: "/nft/avatar/classic.png", kicker: "Avatar / River-valley trainer",
      legend: [
        "Blue cap, steady hands, a Firix at heel. The Classic is the trainer every story in Chikoria starts with: raised on the river, first egg from the gathering banks, first win in the Chikiseum's small ring.",
      ],
    },
    electro: {
      name: "The Electro", art: "/nft/avatar/electro.png", kicker: "Avatar / Storm Peaks runner",
      legend: [
        "The Electro grew up under Grovador's clouds and never learned to fear a storm. Yellow jacket, lightning at the seams, and the fastest hands in the Chikiseum when a Storm card needs to be played on time.",
      ],
    },
    fire: {
      name: "The Blaze", art: "/nft/avatar/fire.png", kicker: "Avatar / Ember Ridge climber",
      legend: [
        "Only a few trainers have climbed the Ember Ridge to where Dragonos waits. The Blaze is one, and wears the red of the summit to prove it. Fire Chikimons take to them at once.",
      ],
    },
    night: {
      name: "The Night", art: "/nft/avatar/night.png", kicker: "Avatar / Evening watch",
      legend: [
        "The Night walks with Vesperos. Dark coat, crescent at the collar, and a habit of turning up at the Wicked Temple after sundown when Grimwick's creatures are boldest and the treasure vault is least guarded.",
      ],
    },
    sailor: {
      name: "The Sailor", art: "/nft/avatar/sailor.png", kicker: "Avatar / Coast fisher",
      legend: [
        "Every fish caught on Chikoria's coast has been caught in the Sailor's wake at least once. Teal coat, anchor at the collar, and an understanding with Galador that keeps the crossings calm.",
      ],
    },
  },
  mount: {
    boar: {
      name: "Boar", art: "/nft/mount/boar.png", kicker: "Chikimount / Wildwood",
      legend: ["A Wildwood boar saddled for the autumn woods. Sure-footed on root and rock, it is the mount that carries gatherers into the deep groves and back out again before dark."],
    },
    chicken: {
      name: "Chicken", art: "/nft/mount/chicken.png", kicker: "Chikimount / Farmstead",
      legend: ["The farmstead chicken is the first mount most trainers ever ride, and the one they are fondest of. It is not fast, but it is never lost, and it always knows where the eggs are."],
    },
    emmanuel: {
      name: "Emmanuel", art: "/nft/mount/emmanuel.png", kicker: "Chikimount / Farmstead",
      legend: ["Emmanuel the emu arrived at the farmstead by no route anyone can explain and has refused to leave. He is tall enough to see over the fences and curious enough to walk through them."],
    },
    gator: {
      name: "Gator", art: "/nft/mount/gator.png", kicker: "Chikimount / River marsh",
      legend: ["The marsh gator takes trainers where the Chikoria River goes wide and slow. It swims as well as it walks, and it is the only mount that can follow Rivaros along the flooded banks."],
    },
    griffin: {
      name: "Griffin", art: "/nft/mount/griffin.png", kicker: "Chikimount / Dawn Spire",
      legend: ["A griffin of the Dawn Spire, half eagle, half lion, and the only mount that can carry a trainer between the floating isles. Adalor tolerates it; nobody else is allowed that high."],
    },
    horse: {
      name: "Royal Horse", art: "/nft/mount/horse.png", kicker: "Chikimount / Castle stables",
      legend: ["The castle's own stock, in blue and gold barding. It carries the Knight to the Wicked Temple road at dawn and stands at the Chikiseum gate while the bouts are on."],
    },
    momota: {
      name: "Momota", art: "/nft/mount/momota.png", kicker: "Chikimount / Northern ice",
      legend: ["A snow bear from Borealon's ice shelf, with an orange cone it found on the harbour and will not take off. Momota is enormous, gentle, and warm to ride through a blizzard."],
    },
    pesto: {
      name: "Pesto", art: "/nft/mount/pesto.png", kicker: "Chikimount / Northern ice",
      legend: ["Pesto is a penguin chick that never stopped growing. Too big to fly and too heavy to hurry, he slides trainers down the northern ice on his belly and asks for fish at the bottom."],
    },
    snowball: {
      name: "Snowball", art: "/nft/mount/snowball.png", kicker: "Chikimount / Chikiseum",
      legend: ["A cockatoo that dances to the Chikiseum's drums and is happiest when a crowd is watching. Snowball flies short hops with a rider and long ones alone, usually to wherever the music is."],
    },
    tillman: {
      name: "Tillman", art: "/nft/mount/tillman.png", kicker: "Chikimount / The coast",
      legend: ["Tillman the bulldog rides a skateboard along the coast road faster than most mounts can run. He does not walk anywhere if there is a slope available."],
    },
    wolf: {
      name: "Night Wolf", art: "/nft/mount/wolf.png", kicker: "Chikimount / Storm Peaks",
      legend: ["A grey wolf from the snowfields below the Storm Peaks, saddled in leather and blue. It runs the moonlit roads Vesperos watches and never loses the trail."],
    },
    wrinkle: {
      name: "Wrinkle", art: "/nft/mount/wrinkle.png", kicker: "Chikimount / Chikoria Cup",
      legend: ["Wrinkle the duck runs the Chikoria Cup road race every year and has a medal to show for it. Trainers ride him for the fun of it; nobody has ever ridden him fast."],
    },
  },
};
