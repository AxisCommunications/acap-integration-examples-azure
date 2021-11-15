*Copyright (C) 2021, Axis Communications AB, Lund, Sweden. All Rights Reserved.*

# Integration between Axis devices and Azure

## Introduction

[AXIS Camera Application Platform (ACAP)](https://www.axis.com/support/developer-support/axis-camera-application-platform) is an open application platform that enables members of [Axis Application Development Partner (ADP)](https://www.axis.com/partners/adp-partner-program) Program to develop applications that can be downloaded and installed on Axis network cameras and video encoders.

[Azure](https://azure.microsoft.com) is a platform in the cloud that provides highly reliable, scalable, low-cost infrastructure to individuals, companies, and governments.

This repository focuses on providing examples where we create the integration between the Axis device and Azure. If you are interested in camera applications and the different API surfaces an application can use, please visit our related repository [AxisCommunications/acap3-examples](https://github.com/AxisCommunications/acap3-examples/).

## Example applications

The repository contains a set of examples, each tailored towards a specific problem. All examples have a README file in its directory which shows overview, example directory structure and step-by-step instructions on how to deploy the Azure infrastructure and how to configure the camera to interact with Azure.

If you find yourself wishing there was another example more relevant to your use case, please don't hesitate to [start a discussion](https://github.com/AxisCommunications/acap-integration-examples-azure/discussions/new) or [open a new issue](https://github.com/AxisCommunications/acap-integration-examples-azure/issues/new/choose).

- [images-to-azure-storage-account](./images-to-azure-storage-account/)
  - This example covers sending images from a camera to a storage account in Azure
- [telemetry-to-azure-iot-edge](./telemetry-to-azure-iot-edge/)
  - This example covers sending telemetry from a camera to IoT Edge on-premises
- [telemetry-to-azure-iot-hub](./telemetry-to-azure-iot-hub/)
  - This example covers sending telemetry from a camera to an IoT Hub in Azure

## License

[Apache 2.0](./LICENSE)
