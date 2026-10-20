// Keep roads, transit stations, shops, and landmarks visible on the dark map.
const darkMapStyle = r'''[
  {"elementType":"geometry","stylers":[{"color":"#172820"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#d5e2cb"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#172820"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#587660"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#172820"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#1c3428"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#284235"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#c9dfc0"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill","stylers":[{"color":"#e1eccf"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#234735"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3a5142"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#243a2e"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#66866b"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f0f4db"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#82ab7d"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#5f9367"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#dfe9b9"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#172e30"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#aac6c0"}]}
]''';
