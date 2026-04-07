# BHNM API: `/devices/timeseries-metrics`

## Endpoint

```
POST /fw/index.php?r=restful/devices/timeseries-metrics
Content-Type: multipart/form-data
```

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `password` | Yes | API key |
| `pin` | No | Optional PIN |
| `metricFilterStatGroup` | Yes | e.g. `bandwidth`, `CPU`, `Memory` |
| `metricFilterUnits` | Yes | e.g. `%`, `Bytes/s` |
| `groupFilterBy` | Yes | e.g. `device` |
| `groupFilterValue` | Yes | Device name |
| `timeFrameFilterBy` | Yes | `specific_time` or `time_offset` |
| `timeFrameFilterValueStart` | Conditional | Epoch timestamp (when `timeFrameFilterBy=specific_time`) |
| `timeFrameFilterValueEnd` | Conditional | Epoch timestamp (when `timeFrameFilterBy=specific_time`) |
| `timeFrameFilterValue` | Conditional | e.g. `Last Hour` (when `timeFrameFilterBy=time_offset`) |
| `returnFormatFilterBy` | Yes | e.g. `average` |
| `no_cache` | No | `1` to bypass cache |

## Response Structure

Each metric entry contains:

```json
{
  "deviceIndex": "57",
  "deviceName": "device-name",
  "UID": "74",
  "instanceDescr": "Bandwidth on device-name InterfaceName",
  "metricId": "instance_NNNNNN",
  "oid_perif_title": "Bandwidth",
  "oid_table": "oid_perif",
  "speedIn": "40 Gbits/s",
  "speedOut": "40 Gbits/s",
  "interfaceSpeedsRaw": {
    "In": 40000000000,
    "Out": 40000000000
  },
  "pollingInterval": "1-minute polling",
  "datapointLegend": ["In", "Out"],
  "datapointCount": 5,
  "datapoints": [
    { "<epoch>": "<value>", ... },
    { "<epoch>": "<value>", ... }
  ]
}
```

### Comparison with `get-time-series-metrics`

| Aspect | `get-time-series-metrics` | `timeseries-metrics` |
|---|---|---|
| Content-Type | `application/x-www-form-urlencoded` | `multipart/form-data` |
| Time range | `timeFrameFilterValue` presets only | Also supports `specific_time` with epoch start/end |
| Interface speed | Not included | `speedIn`, `speedOut`, `interfaceSpeedsRaw` |
| Datapoint format | `timeStamp` + `value1`/`value2` per entry | Epoch-keyed objects, one per legend entry |
| % accuracy | Accurate (server-side calculation) | **Bug:** Interfaces with `speedIn`/`speedOut` = null return raw values instead of percentages |

## Known Bug (as of 26.1.02)

When an interface has no speed defined (`speedIn: null`, `speedOut: null`, `interfaceSpeedsRaw.In: 0`), the endpoint returns raw byte/bit values instead of percentages when `metricFilterUnits=%`. The `get-time-series-metrics` endpoint does not have this issue.

## Usage Notes for BeNeM

- `get-time-series-metrics` is sufficient for BeNeM's needs (last 24h max, CPU/Memory/Bandwidth/Latency)
- This endpoint is useful for `specific_time` range queries or interface speed display
