// Monochrome map styling keeps roads, transit stops, shops, and landmarks readable.
const darkMapStyle = r'''[
  {"featureType":"all","elementType":"all","stylers":[{"saturation":-100}]},
  {"elementType":"geometry","stylers":[{"color":"#090909"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#e5e5e5"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#080808"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#747474"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#0b0b0b"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#151515"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1b1b1b"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#cecece"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill","stylers":[{"color":"#f0f0f0"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#222222"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#383838"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#202020"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#777777"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#979797"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#c9c9c9"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#111111"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#bcbcbc"}]}
]''';
