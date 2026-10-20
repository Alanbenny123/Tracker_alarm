// Keep roads, transit stations, shops, and landmarks visible on the dark map.
const darkMapStyle = r'''[
  {"elementType":"geometry","stylers":[{"color":"#130b0a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#d4b9a9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#130b0a"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#754633"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#130b0a"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#20120f"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#281714"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d7ac96"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill","stylers":[{"color":"#f1c9aa"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#24201a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3b211b"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#26130f"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#82402a"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffe1b8"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#b94e2f"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#c95332"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#ffd175"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#121519"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#b9ada9"}]}
]''';
