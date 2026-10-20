// Keep roads, transit stations, shops, and landmarks visible on the dark map.
const darkMapStyle = r'''[
  {"elementType":"geometry","stylers":[{"color":"#171515"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#c8b8a8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#171515"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#665044"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#171515"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#24211c"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#292321"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#c6ad98"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill","stylers":[{"color":"#eed2b7"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#25291f"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3b3029"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#29211d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#765037"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffe0bd"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#a64f1b"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#a95824"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#ffbc7a"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#171d22"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#b6b8ba"}]}
]''';
