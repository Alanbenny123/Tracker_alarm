// Keep roads, transit stations, shops, and landmarks visible on the dark map.
const darkMapStyle = r'''[
  {"elementType":"geometry","stylers":[{"color":"#172328"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b7cccb"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#172328"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#426269"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#172328"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#1b302f"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#26383a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#a8cbc6"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill","stylers":[{"color":"#c6dbd4"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1c3834"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#31464a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#233438"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#526b70"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#e1e9dd"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#247b7e"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#23666b"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#7bdfdb"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e2b33"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#75bfc6"}]}
]''';
