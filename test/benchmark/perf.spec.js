import { decodeGeom } from '../../src/renderer/decoder';
import GeoJSON from '../../src/sources/GeoJSON';

const geojson = new GeoJSON({
    "type": "Feature",
    "properties": {
      "name": "Bermuda Triangle",
      "area": 1150180
    },
    "geometry": {
      "type": "Polygon",
      "coordinates": [
        [
          [-64.73, 32.31],
          [-80.19, 25.76],
          [-66.09, 18.43],
          [-64.73, 32.31]
        ]
      ]
    }
  });
const polygonGeometry = geojson._decodeGeometry();

falcon.benchmark('decodePolygon', () => {
    decodeGeom('polygon', polygonGeometry);
}, {runs: 1});
