import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mapsforge_flutter/core.dart';
import 'package:mapsforge_flutter/datastore.dart';
import 'package:mapsforge_flutter/src/mapfile/writer/subfile_filler.dart';
import 'package:mapsforge_flutter/src/mapfile/writer/wayholder.dart';
import 'package:mapsforge_flutter/src/model/zoomlevel_range.dart';

main() async {
  final _log = new Logger('CopyPbfToMapfileTest');

  testWidgets("Reduce number of points", (WidgetTester tester) async {
    _initLogging();

    MemoryDatastore datastore = MemoryDatastore();
    List<ILatLong> points = [
      const LatLong(43.536831, 7.532992),
      const LatLong(43.535270, 7.530473),
      const LatLong(43.533709, 7.527954),
      const LatLong(43.532148, 7.525435),
      const LatLong(43.530587, 7.522916),
      const LatLong(43.529026, 7.520397),
      const LatLong(43.527465, 7.517878),
      const LatLong(43.525904, 7.515359),
      const LatLong(43.524342, 7.512840),
      const LatLong(43.522781, 7.510321),
      const LatLong(43.521220, 7.507802),
      const LatLong(43.519659, 7.505283),
      const LatLong(43.518097, 7.502764),
      const LatLong(43.516536, 7.500245),
      const LatLong(43.518709, 7.499393),
      const LatLong(43.520881, 7.498542),
      const LatLong(43.523054, 7.497691),
      const LatLong(43.525226, 7.496840),
      const LatLong(43.527399, 7.495988),
      const LatLong(43.529571, 7.495137),
      const LatLong(43.531743, 7.494286),
      const LatLong(43.533915, 7.493435),
      const LatLong(43.536087, 7.492583),
      const LatLong(43.538260, 7.491732),
      const LatLong(43.540431, 7.490881),
      const LatLong(43.542603, 7.490030),
      const LatLong(43.544775, 7.489178),
      const LatLong(43.546947, 7.488327),
      const LatLong(43.549118, 7.487476),
      const LatLong(43.551290, 7.486625),
      const LatLong(43.553461, 7.485773),
      const LatLong(43.555633, 7.484922),
      const LatLong(43.557804, 7.484071),
      const LatLong(43.559975, 7.483219),
      const LatLong(43.562146, 7.482368),
      const LatLong(43.564318, 7.481517),
      const LatLong(43.566489, 7.480666),
      const LatLong(43.568659, 7.479814),
      const LatLong(43.570830, 7.478963),
      const LatLong(43.573001, 7.478112),
      const LatLong(43.575172, 7.477261),
      const LatLong(43.577342, 7.476409),
      const LatLong(43.579513, 7.475558),
      const LatLong(43.581683, 7.474707),
      const LatLong(43.583854, 7.473856),
      const LatLong(43.586024, 7.473004),
      const LatLong(43.588194, 7.472153),
      const LatLong(43.590364, 7.471302),
      const LatLong(43.592534, 7.470451),
      const LatLong(43.594704, 7.469599),
      const LatLong(43.596874, 7.468748),
      const LatLong(43.599044, 7.467897),
      const LatLong(43.601214, 7.467045),
      const LatLong(43.603384, 7.466194),
      const LatLong(43.605553, 7.465343),
      const LatLong(43.607723, 7.464492),
      const LatLong(43.609892, 7.463640),
      const LatLong(43.612061, 7.462789),
      const LatLong(43.614231, 7.461938),
      const LatLong(43.616400, 7.461087),
      const LatLong(43.618569, 7.460235),
      const LatLong(43.620738, 7.459384),
      const LatLong(43.622907, 7.458533),
      const LatLong(43.625076, 7.457682),
      const LatLong(43.627245, 7.456830),
      const LatLong(43.629413, 7.455979),
      const LatLong(43.631582, 7.455128),
      const LatLong(43.633751, 7.454277),
      const LatLong(43.635919, 7.453425),
      const LatLong(43.638088, 7.452574),
      const LatLong(43.640256, 7.451723),
      const LatLong(43.642424, 7.450871),
      const LatLong(43.644592, 7.450020),
      const LatLong(43.646760, 7.449169),
      const LatLong(43.648928, 7.448318),
      const LatLong(43.651096, 7.447466),
      const LatLong(43.653264, 7.446615),
      const LatLong(43.655432, 7.445764),
      const LatLong(43.657600, 7.444913),
      const LatLong(43.659767, 7.444061),
      const LatLong(43.661935, 7.443210),
      const LatLong(43.664102, 7.442359),
      const LatLong(43.666270, 7.441508),
      const LatLong(43.668437, 7.440656),
      const LatLong(43.670604, 7.439805),
      const LatLong(43.672772, 7.438954),
      const LatLong(43.674939, 7.438103),
      const LatLong(43.677106, 7.437251),
      const LatLong(43.679273, 7.436400),
      const LatLong(43.681439, 7.435549),
      const LatLong(43.683606, 7.434697),
      const LatLong(43.685773, 7.433846),
      const LatLong(43.687939, 7.432995),
      const LatLong(43.690106, 7.432144),
      const LatLong(43.692272, 7.431292),
      const LatLong(43.694439, 7.430441),
      const LatLong(43.696605, 7.429590),
      const LatLong(43.698771, 7.428739),
      const LatLong(43.700938, 7.427887),
      const LatLong(43.703104, 7.427036),
      const LatLong(43.705270, 7.426185),
      const LatLong(43.707435, 7.425334),
      const LatLong(43.709601, 7.424482),
      const LatLong(43.711767, 7.423631),
      const LatLong(43.713933, 7.422780),
      const LatLong(43.716098, 7.421929),
      const LatLong(43.718264, 7.421077),
      const LatLong(43.720429, 7.420226),
      const LatLong(43.722595, 7.419375),
      const LatLong(43.724760, 7.418523),
      const LatLong(43.724902, 7.418264),
      const LatLong(43.725013, 7.418041),
      const LatLong(43.725176, 7.417721),
      const LatLong(43.725587, 7.416931),
      const LatLong(43.726264, 7.415611),
      const LatLong(43.727149, 7.413833),
      const LatLong(43.727422, 7.413300),
      const LatLong(43.727871, 7.412461),
      const LatLong(43.727942, 7.412336),
      const LatLong(43.728096, 7.412042),
      const LatLong(43.728150, 7.411941),
      const LatLong(43.728312, 7.411624),
      const LatLong(43.728387, 7.411478),
      const LatLong(43.728481, 7.411291),
      const LatLong(43.728535, 7.411184),
      const LatLong(43.728806, 7.410654),
      const LatLong(43.728882, 7.410493),
      const LatLong(43.728905, 7.410445),
      const LatLong(43.728925, 7.410405),
      const LatLong(43.728954, 7.410339),
      const LatLong(43.729003, 7.410239),
      const LatLong(43.729031, 7.410184),
      const LatLong(43.729125, 7.409994),
      const LatLong(43.729274, 7.409676),
      const LatLong(43.729380, 7.409451),
      const LatLong(43.729395, 7.409418),
      const LatLong(43.729419, 7.409377),
      const LatLong(43.729544, 7.409080),
      const LatLong(43.729578, 7.409028),
      const LatLong(43.729610, 7.409050),
      const LatLong(43.729689, 7.409151),
      const LatLong(43.729801, 7.409202),
      const LatLong(43.729839, 7.409214),
      const LatLong(43.729883, 7.409260),
      const LatLong(43.729984, 7.409322),
      const LatLong(43.730034, 7.409377),
      const LatLong(43.730046, 7.409427),
      const LatLong(43.730116, 7.409527),
      const LatLong(43.730193, 7.409610),
      const LatLong(43.730285, 7.409694),
      const LatLong(43.730379, 7.409728),
      const LatLong(43.730731, 7.410019),
      const LatLong(43.730812, 7.410112),
      const LatLong(43.730892, 7.410208),
      const LatLong(43.730943, 7.410331),
      const LatLong(43.730966, 7.410399),
      const LatLong(43.730989, 7.410429),
      const LatLong(43.731014, 7.410455),
      const LatLong(43.731051, 7.410497),
      const LatLong(43.731053, 7.410498),
      const LatLong(43.731106, 7.410545),
      const LatLong(43.731129, 7.410644),
      const LatLong(43.731163, 7.410727),
      const LatLong(43.731191, 7.410784),
      const LatLong(43.731219, 7.410844),
      const LatLong(43.731251, 7.410901),
      const LatLong(43.731277, 7.410943),
      const LatLong(43.731356, 7.411123),
      const LatLong(43.731398, 7.411244),
      const LatLong(43.731495, 7.411362),
      const LatLong(43.731533, 7.411466),
      const LatLong(43.731570, 7.411600),
      const LatLong(43.731600, 7.411725),
      const LatLong(43.731618, 7.411795),
      const LatLong(43.731625, 7.411897),
      const LatLong(43.731626, 7.411965),
      const LatLong(43.731623, 7.412036),
      const LatLong(43.731619, 7.412102),
      const LatLong(43.731608, 7.412176),
      const LatLong(43.731595, 7.412248),
      const LatLong(43.731584, 7.412320),
      const LatLong(43.731573, 7.412383),
      const LatLong(43.731560, 7.412457),
      const LatLong(43.731571, 7.412525),
      const LatLong(43.731604, 7.412659),
      const LatLong(43.731612, 7.412677),
      const LatLong(43.731635, 7.412671),
      const LatLong(43.731650, 7.412718),
      const LatLong(43.731666, 7.412791),
      const LatLong(43.731674, 7.412810),
      const LatLong(43.731664, 7.412865),
      const LatLong(43.731691, 7.412906),
      const LatLong(43.731796, 7.412934),
      const LatLong(43.731846, 7.412952),
      const LatLong(43.732207, 7.412986),
      const LatLong(43.732271, 7.412990),
      const LatLong(43.732412, 7.413003),
      const LatLong(43.732489, 7.413017),
      const LatLong(43.732542, 7.413021),
      const LatLong(43.732571, 7.413027),
      const LatLong(43.732617, 7.413045),
      const LatLong(43.732781, 7.413092),
      const LatLong(43.732824, 7.413105),
      const LatLong(43.732961, 7.413078),
      const LatLong(43.733009, 7.413054),
      const LatLong(43.733077, 7.413004),
      const LatLong(43.733206, 7.412856),
      const LatLong(43.733348, 7.412724),
      const LatLong(43.733456, 7.412674),
      const LatLong(43.733652, 7.412704),
      const LatLong(43.733720, 7.412714),
      const LatLong(43.733771, 7.412722),
      const LatLong(43.733834, 7.412732),
      const LatLong(43.733956, 7.412817),
      const LatLong(43.733965, 7.412815),
      const LatLong(43.734022, 7.412751),
      const LatLong(43.734064, 7.412669),
      const LatLong(43.734097, 7.412614),
      const LatLong(43.734124, 7.412566),
      const LatLong(43.734232, 7.412445),
      const LatLong(43.734334, 7.412336),
      const LatLong(43.734363, 7.412388),
      const LatLong(43.734481, 7.412614),
      const LatLong(43.734555, 7.412690),
      const LatLong(43.734669, 7.412681),
      const LatLong(43.734695, 7.412701),
      const LatLong(43.734833, 7.412906),
      const LatLong(43.735426, 7.413817),
      const LatLong(43.735611, 7.414089),
      const LatLong(43.735917, 7.414482),
      const LatLong(43.736241, 7.414898),
      const LatLong(43.736295, 7.414990),
      const LatLong(43.736485, 7.415310),
      const LatLong(43.736519, 7.415362),
      const LatLong(43.736730, 7.415729),
      const LatLong(43.736824, 7.415880),
      const LatLong(43.736881, 7.415973),
      const LatLong(43.737399, 7.416868),
      const LatLong(43.737881, 7.417612),
      const LatLong(43.737890, 7.417626),
      const LatLong(43.738695, 7.418854),
      const LatLong(43.738888, 7.419148),
      const LatLong(43.739102, 7.419476),
      const LatLong(43.739280, 7.419772),
      const LatLong(43.739395, 7.419951),
      const LatLong(43.739413, 7.419978),
      const LatLong(43.739546, 7.420239),
      const LatLong(43.739740, 7.420572),
      const LatLong(43.739696, 7.420632),
      const LatLong(43.739791, 7.420759),
      const LatLong(43.740553, 7.421636),
      const LatLong(43.740624, 7.421717),
      const LatLong(43.740703, 7.421599),
      const LatLong(43.740802, 7.421676),
      const LatLong(43.740912, 7.421740),
      const LatLong(43.741119, 7.421860),
      const LatLong(43.741124, 7.421939),
      const LatLong(43.741289, 7.422073),
      const LatLong(43.741414, 7.422222),
      const LatLong(43.741364, 7.422354),
      const LatLong(43.741694, 7.422967),
      const LatLong(43.741671, 7.423021),
      const LatLong(43.741516, 7.423302),
      const LatLong(43.741460, 7.423413),
      const LatLong(43.741317, 7.423675),
      const LatLong(43.740969, 7.424298),
      const LatLong(43.740852, 7.424507),
      const LatLong(43.741587, 7.425025),
      const LatLong(43.741494, 7.425187),
      const LatLong(43.741433, 7.425287),
      const LatLong(43.741455, 7.425337),
      const LatLong(43.741478, 7.425366),
      const LatLong(43.741611, 7.425441),
      const LatLong(43.741636, 7.425455),
      const LatLong(43.741697, 7.425549),
      const LatLong(43.741757, 7.425742),
      const LatLong(43.741876, 7.425878),
      const LatLong(43.741985, 7.425990),
      const LatLong(43.742169, 7.426082),
      const LatLong(43.742230, 7.426146),
      const LatLong(43.742333, 7.426299),
      const LatLong(43.742648, 7.426677),
      const LatLong(43.742709, 7.426718),
      const LatLong(43.742841, 7.426743),
      const LatLong(43.742891, 7.426772),
      const LatLong(43.742941, 7.426792),
      const LatLong(43.743156, 7.426950),
      const LatLong(43.743227, 7.427019),
      const LatLong(43.743296, 7.427125),
      const LatLong(43.743429, 7.427419),
      const LatLong(43.743586, 7.427658),
      const LatLong(43.743774, 7.427875),
      const LatLong(43.743801, 7.427930),
      const LatLong(43.743945, 7.428058),
      const LatLong(43.744091, 7.428108),
      const LatLong(43.744501, 7.428109),
      const LatLong(43.744574, 7.428139),
      const LatLong(43.744759, 7.428286),
      const LatLong(43.744918, 7.428388),
      const LatLong(43.745011, 7.428528),
      const LatLong(43.745113, 7.428563),
      const LatLong(43.745183, 7.428625),
      const LatLong(43.745290, 7.428615),
      const LatLong(43.745442, 7.428678),
      const LatLong(43.745481, 7.428676),
      const LatLong(43.745561, 7.428614),
      const LatLong(43.745627, 7.428584),
      const LatLong(43.745747, 7.428589),
      const LatLong(43.745932, 7.428689),
      const LatLong(43.745929, 7.428713),
      const LatLong(43.746017, 7.428755),
      const LatLong(43.746043, 7.428610),
      const LatLong(43.746413, 7.428742),
      const LatLong(43.746483, 7.428763),
      const LatLong(43.746564, 7.428787),
      const LatLong(43.746570, 7.428789),
      const LatLong(43.746642, 7.428905),
      const LatLong(43.746822, 7.429260),
      const LatLong(43.746862, 7.429288),
      const LatLong(43.748043, 7.429797),
      const LatLong(43.748062, 7.429809),
      const LatLong(43.748215, 7.430388),
      const LatLong(43.748226, 7.430439),
      const LatLong(43.748248, 7.430442),
      const LatLong(43.748345, 7.430441),
      const LatLong(43.748602, 7.430486),
      const LatLong(43.748651, 7.430506),
      const LatLong(43.748696, 7.430542),
      const LatLong(43.748779, 7.430621),
      const LatLong(43.748933, 7.430625),
      const LatLong(43.748981, 7.430628),
      const LatLong(43.749024, 7.430641),
      const LatLong(43.749022, 7.430708),
      const LatLong(43.748992, 7.430730),
      const LatLong(43.748964, 7.430761),
      const LatLong(43.748953, 7.430772),
      const LatLong(43.748936, 7.430817),
      const LatLong(43.748926, 7.430953),
      const LatLong(43.748920, 7.431100),
      const LatLong(43.748925, 7.431173),
      const LatLong(43.748938, 7.431307),
      const LatLong(43.748955, 7.431355),
      const LatLong(43.748954, 7.431422),
      const LatLong(43.748945, 7.431447),
      const LatLong(43.748866, 7.431632),
      const LatLong(43.748854, 7.431694),
      const LatLong(43.748851, 7.431726),
      const LatLong(43.748857, 7.431810),
      const LatLong(43.748867, 7.431909),
      const LatLong(43.748893, 7.431986),
      const LatLong(43.748929, 7.432029),
      const LatLong(43.748970, 7.432083),
      const LatLong(43.748977, 7.432105),
      const LatLong(43.749136, 7.432254),
      const LatLong(43.749203, 7.432329),
      const LatLong(43.749255, 7.432410),
      const LatLong(43.749263, 7.432481),
      const LatLong(43.749384, 7.433112),
      const LatLong(43.749425, 7.433320),
      const LatLong(43.749448, 7.433449),
      const LatLong(43.749458, 7.433505),
      const LatLong(43.749492, 7.433689),
      const LatLong(43.749558, 7.433886),
      const LatLong(43.749572, 7.433928),
      const LatLong(43.749695, 7.434284),
      const LatLong(43.749815, 7.434627),
      const LatLong(43.749866, 7.434786),
      const LatLong(43.749867, 7.434787),
      const LatLong(43.749912, 7.434939),
      const LatLong(43.749962, 7.435557),
      const LatLong(43.749992, 7.435978),
      const LatLong(43.750294, 7.436380),
      const LatLong(43.751214, 7.437594),
      const LatLong(43.751285, 7.437342),
      const LatLong(43.751605, 7.436772),
      const LatLong(43.751917, 7.436885),
      const LatLong(43.751916, 7.436936),
      const LatLong(43.751908, 7.437033),
      const LatLong(43.751887, 7.437135),
      const LatLong(43.751820, 7.437331),
      const LatLong(43.751804, 7.437390),
      const LatLong(43.751795, 7.437461),
      const LatLong(43.751797, 7.437655),
      const LatLong(43.751796, 7.437719),
      const LatLong(43.751783, 7.437780),
      const LatLong(43.751767, 7.437822),
      const LatLong(43.751710, 7.437943),
      const LatLong(43.751343, 7.438569),
      const LatLong(43.751292, 7.438636),
      const LatLong(43.751246, 7.438675),
      const LatLong(43.751187, 7.438699),
      const LatLong(43.751149, 7.438705),
      const LatLong(43.751113, 7.438705),
      const LatLong(43.751052, 7.438703),
      const LatLong(43.750966, 7.438684),
      const LatLong(43.750795, 7.438669),
      const LatLong(43.750692, 7.438576),
      const LatLong(43.750547, 7.438472),
      const LatLong(43.750499, 7.438452),
      const LatLong(43.750454, 7.438446),
      const LatLong(43.750415, 7.438451),
      const LatLong(43.750377, 7.438464),
      const LatLong(43.750198, 7.438583),
      const LatLong(43.750123, 7.438572),
      const LatLong(43.750017, 7.438587),
      const LatLong(43.749963, 7.438615),
      const LatLong(43.749902, 7.438655),
      const LatLong(43.749886, 7.438656),
      const LatLong(43.749868, 7.438649),
      const LatLong(43.749652, 7.438472),
      const LatLong(43.749553, 7.438406),
      const LatLong(43.749522, 7.438395),
      const LatLong(43.749488, 7.438393),
      const LatLong(43.749458, 7.438397),
      const LatLong(43.749432, 7.438406),
      const LatLong(43.749422, 7.438411),
      const LatLong(43.749407, 7.438421),
      const LatLong(43.749394, 7.438431),
      const LatLong(43.749383, 7.438446),
      const LatLong(43.749011, 7.439171),
      const LatLong(43.747688, 7.441780),
      const LatLong(43.746315, 7.444444),
      const LatLong(43.744942, 7.447108),
      const LatLong(43.743568, 7.449771),
      const LatLong(43.742195, 7.452435),
      const LatLong(43.740037, 7.453283),
      const LatLong(43.737879, 7.454131),
      const LatLong(43.735721, 7.454979),
      const LatLong(43.733562, 7.455827),
      const LatLong(43.731404, 7.456675),
      const LatLong(43.729245, 7.457523),
      const LatLong(43.727087, 7.458371),
      const LatLong(43.724928, 7.459219),
      const LatLong(43.722770, 7.460067),
      const LatLong(43.720611, 7.460915),
      const LatLong(43.718452, 7.461763),
      const LatLong(43.716293, 7.462611),
      const LatLong(43.714134, 7.463459),
      const LatLong(43.711975, 7.464307),
      const LatLong(43.709816, 7.465155),
      const LatLong(43.707657, 7.466003),
      const LatLong(43.705497, 7.466851),
      const LatLong(43.703338, 7.467699),
      const LatLong(43.701178, 7.468546),
      const LatLong(43.699019, 7.469394),
      const LatLong(43.696859, 7.470242),
      const LatLong(43.694699, 7.471090),
      const LatLong(43.692540, 7.471938),
      const LatLong(43.690380, 7.472786),
      const LatLong(43.688220, 7.473634),
      const LatLong(43.686060, 7.474482),
      const LatLong(43.683900, 7.475330),
      const LatLong(43.681740, 7.476178),
      const LatLong(43.679579, 7.477026),
      const LatLong(43.677419, 7.477874),
      const LatLong(43.675259, 7.478722),
      const LatLong(43.673098, 7.479570),
      const LatLong(43.670938, 7.480418),
      const LatLong(43.668777, 7.481266),
      const LatLong(43.666616, 7.482114),
      const LatLong(43.664455, 7.482962),
      const LatLong(43.662295, 7.483810),
      const LatLong(43.660134, 7.484658),
      const LatLong(43.657973, 7.485506),
      const LatLong(43.655811, 7.486354),
      const LatLong(43.653650, 7.487202),
      const LatLong(43.651489, 7.488050),
      const LatLong(43.649328, 7.488898),
      const LatLong(43.647166, 7.489746),
      const LatLong(43.645005, 7.490594),
      const LatLong(43.642843, 7.491442),
      const LatLong(43.640682, 7.492289),
      const LatLong(43.638520, 7.493137),
      const LatLong(43.636358, 7.493985),
      const LatLong(43.634196, 7.494833),
      const LatLong(43.632034, 7.495681),
      const LatLong(43.629872, 7.496529),
      const LatLong(43.627710, 7.497377),
      const LatLong(43.625548, 7.498225),
      const LatLong(43.623386, 7.499073),
      const LatLong(43.621223, 7.499921),
      const LatLong(43.619061, 7.500769),
      const LatLong(43.616898, 7.501617),
      const LatLong(43.614736, 7.502465),
      const LatLong(43.612573, 7.503313),
      const LatLong(43.610410, 7.504161),
      const LatLong(43.608247, 7.505009),
      const LatLong(43.606085, 7.505857),
      const LatLong(43.603922, 7.506705),
      const LatLong(43.601759, 7.507553),
      const LatLong(43.599595, 7.508401),
      const LatLong(43.597432, 7.509249),
      const LatLong(43.595269, 7.510097),
      const LatLong(43.593106, 7.510945),
      const LatLong(43.590942, 7.511793),
      const LatLong(43.588779, 7.512641),
      const LatLong(43.586615, 7.513489),
      const LatLong(43.584451, 7.514337),
      const LatLong(43.582288, 7.515185),
      const LatLong(43.580124, 7.516032),
      const LatLong(43.577960, 7.516880),
      const LatLong(43.575796, 7.517728),
      const LatLong(43.573632, 7.518576),
      const LatLong(43.571468, 7.519424),
      const LatLong(43.569303, 7.520272),
      const LatLong(43.567139, 7.521120),
      const LatLong(43.564975, 7.521968),
      const LatLong(43.562810, 7.522816),
      const LatLong(43.560646, 7.523664),
      const LatLong(43.558481, 7.524512),
      const LatLong(43.556317, 7.525360),
      const LatLong(43.554152, 7.526208),
      const LatLong(43.551987, 7.527056),
      const LatLong(43.549822, 7.527904),
      const LatLong(43.547657, 7.528752),
      const LatLong(43.545492, 7.529600),
      const LatLong(43.543327, 7.530448),
      const LatLong(43.541162, 7.531296),
      const LatLong(43.538996, 7.532144),
      const LatLong(43.536831, 7.532992)
    ];
    points.forEach((latlong) {
      int len = points.where((test) => test == latlong).length;
      if (len > 1) {
        print("Found duplicate: $latlong $len");
      }
    });
    Way way = Way(0, [const Tag("admin_level", "2")], [points], null);
    assert(points.length == 520, "Length is wrong: ${points.length}");
    BoundingBox boundingBox = BoundingBox.fromLatLongs(points);
    assert(boundingBox == const BoundingBox(43.516536, 7.409028, 43.751917, 7.532992), "Bounding box is wrong: $boundingBox");

    // DisplayModel is needed for the tilesize
    DisplayModel();
    SubfileFiller subfileFiller = SubfileFiller(const ZoomlevelRange(12, 15), const BoundingBox(-90, -180, 90, 180), 10);
    Wayholder wayholder = Wayholder.fromWay(way);
    List<Wayholder> wayholders = subfileFiller.prepareWays(const ZoomlevelRange(0, 20), [wayholder]);
    wayholder = wayholders.first;
    LatLongUtils.printLatLongs(way);
    assert(way.latLongs[0].length == 35, "wrong size: ${way.latLongs[0].length}");
    boundingBox = BoundingBox.fromLatLongs(way.latLongs[0]);
    assert(boundingBox == const BoundingBox(43.516536, 7.409028, 43.751917, 7.532992), "Bounding box is wrong: $boundingBox");
  });
}

//////////////////////////////////////////////////////////////////////////////

void _initLogging() {
// Print output to console.
  Logger.root.onRecord.listen((LogRecord r) {
    print('${r.time}\t${r.loggerName}\t[${r.level.name}]:\t${r.message}');
  });
  Logger.root.level = Level.FINEST;
}
