*Copyright (C) 2022, Axis Communications AB, Lund, Sweden. All Rights Reserved.*

<!-- omit in toc -->
# Telemetry to Azure IoT Edge

[![Build telemetry-to-azure-iot-edge](https://github.com/AxisCommunications/acap-integration-examples-azure/actions/workflows/telemetry-to-azure-iot-edge.yml/badge.svg)](https://github.com/AxisCommunications/acap-integration-examples-azure/actions/workflows/telemetry-to-azure-iot-edge.yml)
[![Lint codebase](https://github.com/AxisCommunications/acap-integration-examples-azure/actions/workflows/lint.yml/badge.svg)](https://github.com/AxisCommunications/acap-integration-examples-azure/actions/workflows/lint.yml)
![Ready for use in production](https://img.shields.io/badge/Ready%20for%20use%20in%20production-No-red)

This directory hosts the necessary code to follow the instructions detailed in [Send telemetry to Azure IoT Edge](https://developer.axis.com/analytics/how-to-guides/send-telemetry-to-azure-iot-edge) on Axis Developer Documentation.

## File structure

<!-- markdownlint-disable MD040 -->
```
telemetry-to-azure-iot-edge
├── create-certificates.sh         Bash script that creates X.509 certificates for secure
│                                  authentication and communication between camera, Azure IoT Edge
│                                  and Azure IoT Hub.
├── create-cloud-resources.sh      Bash script that creates Azure resources.
├── edge-gateway.deployment.json   Azure IoT Edge gateway deployment manifest that will deploy the
│                                  IoT Edge agent module and the IoT Edge hub module.
└── openssl.cnf                    Configuration file for OpenSSL.
```

## License

[Apache 2.0](./LICENSE)
