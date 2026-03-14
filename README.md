# wowOS

<p align="center">
  <strong>A Data Sovereignty OS for individuals and families</strong>
</p>

<p align="center">
  Built on Linux / Raspberry Pi, wowOS is designed to give users control over their own data, permissions, and intelligent capabilities.
</p>

<p align="center">
  <img alt="Status" src="https://img.shields.io/badge/status-early_stage-active">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Linux%20%2F%20Raspberry%20Pi-blue">
  <img alt="Focus" src="https://img.shields.io/badge/focus-data%20sovereignty-black">
  <img alt="License" src="https://img.shields.io/badge/license-TBD-lightgrey">
  <a href="https://github.com/WowData-labs/wowOS/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/WowData-labs/wowOS?label=Download%20Image&color=brightgreen"></a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Background](#background)
- [What We Mean by Data Sovereignty](#what-we-mean-by-data-sovereignty)
- [Problem Statement](#problem-statement)
- [Project Positioning](#project-positioning)
- [Core Directions](#core-directions)
- [Use Cases](#use-cases)
- [Roadmap](#roadmap)
- [Why Open Source](#why-open-source)
- [Contributing](#contributing)
- [Current Status](#current-status)
- [License](#license)

---

## Overview

**wowOS** is a system-layer project built around the idea of **data sovereignty**.

We believe that future personal intelligence systems, family intelligence systems, and local AI systems should not be built on the default assumption that platforms own user data. Instead, they should be built on a different default:

> **Data should remain inside a system boundary controlled by the user.  
> Permissions should be defined by the user.  
> Intelligent capabilities should serve the user, not displace their control.**

wowOS aims to provide that foundation.

It is not just a single application, not merely a cloud service, and not simply another Raspberry Pi project. It is better understood as a **Linux-based appliance OS / system-layer platform** for personal and family scenarios, focused on:

- local data governance
- authorization and permission boundaries
- data protection
- extensibility through apps and SDKs
- local intelligence integration

---

## Background

As AI, smart home systems, home automation, edge computing, and home server ecosystems continue to evolve, more and more data that should ideally remain local is being pushed into cloud platforms, including:

- household bills and receipts
- financial records
- family member information
- family health data, such as biometrics, medication records, sleep data, and outputs from health devices
- voice content
- images and videos
- device behavior data
- long-term habits and preference data

The issue is not only whether data is uploaded to the cloud, but also:

- where that data is ultimately stored
- who can access it
- how much detail they can access
- whether it is redacted
- whether permissions can be revoked
- whether access is auditable
- whether there is a unified system boundary that constrains AI, applications, and automations

Most intelligent products and AI products still follow a platform-centric model by default:

- data is aggregated by the platform
- permissions are defined by the platform
- capabilities are packaged by the platform
- users consume the output, but rarely control the underlying boundaries

wowOS starts from the opposite direction:

- devices should remain, as much as possible, under user control
- data should remain, as much as possible, user-owned
- permissions should remain, as much as possible, user-defined
- intelligent capabilities should operate within boundaries that are understandable, controllable, and auditable by the user

---

## What We Mean by Data Sovereignty

In the context of wowOS, **data sovereignty** is not just about storing data locally.

We believe a future-facing data sovereignty system must include at least the following dimensions:

### 1. Storage Sovereignty
User data should be stored primarily on devices and systems controlled by the user, rather than being handed over by default to third-party platforms.

### 2. Access Sovereignty
Who can access data, which resources they can access, what operations they can perform, and what data level they can reach should not be implicitly decided by a platform. These boundaries should be explicitly authorized by the system.

### 3. Usage Sovereignty
Data is not only stored; it is continuously used by applications, AI agents, voice assistants, automations, and third-party extensions. The system therefore needs to constrain **who used what data, when, and in what way**.

### 4. Audit Sovereignty
Critical access, authorization events, sensitive operations, and system behavior should be traceable, reviewable, and auditable.

### 5. Collaboration Sovereignty
More and more local intelligence capabilities will participate in personal and family scenarios. The important question is no longer simply whether they can connect, but:

- what they can see
- what they can operate on
- whether data is redacted
- whether permissions can be revoked
- whether an audit trail exists
- whether they always remain inside a user-controlled sovereignty boundary

---

## Problem Statement

wowOS currently focuses on several core problems.

### Local data lacks unified system-level governance
Many local-first projects only solve the problem of storage, but do not systematically solve:

- authorization
- encryption
- redaction
- auditing
- safe app and AI access to local data capabilities

wowOS aims to move these concerns into the system layer and provide them as a shared foundation.

### AI and applications are becoming new data actors
Personal and family data will increasingly be accessed not only by users and traditional apps, but also by:

- AI agents
- automations
- voice assistants
- multimodal analysis services
- third-party extensions
- intelligent applications in family scenarios

Without a stable, clear, and enforceable system boundary, stronger intelligence capabilities can easily mean weaker data boundaries.

### Users need controlled openness, not absolute lockdown
We do not believe the future should be fully closed. Future systems will inevitably include growing ecosystems of apps, extensions, and local intelligence.

The real question is whether openness respects:

- explicit authorization
- least privilege
- graded access
- graded redaction
- revocable permissions
- auditability
- operation within a user-controlled local sovereignty boundary

wowOS is designed as a **controlled-open system**.

### Individuals and families lack a true system foundation built around data sovereignty
There are many excellent open-source projects for NAS, home servers, smart home systems, local AI, self-hosting, and edge devices. There are still very few system foundations built around the idea of **personal and family data sovereignty**.

wowOS aims to become such a foundation.

---

## Project Positioning

The most accurate current positioning of wowOS is:

> **A Linux-based appliance OS / system-layer platform centered on data sovereignty, security boundaries, and local intelligence capabilities.**

It is not currently:

- a general-purpose desktop operating system
- a pure cloud platform
- a project focused on only one vertical application

Instead, it focuses on deeper, longer-term system concerns:

- local data governance
- permission and authorization models
- graded redaction
- encrypted storage
- audit logging
- app store and SDK
- local AI / agent integration
- system boundaries for personal and family scenarios

---

## Core Directions

### Token-based Authorization
Applications and services should not receive unrestricted access to data by default. The system should define access boundaries through tokens, scopes, operations, and data-level constraints.

### Graded Redaction
The system should not operate with only two states: visible or not visible. It should support different data views for different actors and contexts.

### Encrypted Storage
Sensitive data should be stored more securely, with the system managing key paths and access paths consistently.

### Auditability
Key authorizations, accesses, installs, upgrades, and sensitive operations should all be captured by the audit system.

### App Store and SDK
wowOS should not be a system that only maintainers can extend. It needs to gradually establish:

- an app installation model
- an app permission declaration model
- app runtime constraints
- app lifecycle management
- a developer SDK
- a sustainable local application ecosystem

### Local Intelligence Integration
More intelligence will run locally over time. wowOS aims to let local AI, agents, and automations integrate with the system without breaking user data boundaries.

---

## Use Cases

wowOS is particularly relevant for exploring scenarios such as:

- family data management
- family health data management
- local AI / agent integration
- smart home and home automation
- home server / self-hosting
- privacy-sensitive personal intelligence systems
- local application platforms that require explicit authorization and auditability

---

## Roadmap

### Phase 1 — Foundation
- [ ] Build the base system image and service runtime framework
- [ ] Complete the core flow for token authorization, auditing, and encrypted storage
- [ ] Establish the core API and local data access layer
- [ ] Finalize the base image build and delivery pipeline

### Phase 2 — Governance
- [ ] Implement graded redaction
- [ ] Improve data classification and access boundaries
- [ ] Strengthen auditing and sensitive operation logging
- [ ] Connect device-level and service-level key management paths

### Phase 3 — App Platform
- [ ] Define the base app-store protocol
- [ ] Support app install, uninstall, start, and stop
- [ ] Add app permission declaration and install-time approval flow
- [ ] Provide a basic SDK
- [ ] Establish runtime isolation and governance for applications

### Phase 4 — Ecosystem
- [ ] Support app upgrade and rollback
- [ ] Deepen local AI / agent integration
- [ ] Build a more complete wowOS application ecosystem
- [ ] Continuously evolve the system through real household scenarios

---

## Why Open Source

wowOS does not address a single-domain problem. It sits at the intersection of:

- system boundaries
- security and privacy
- permission models
- local AI
- application ecosystems
- smart home / family scenarios
- edge-device delivery
- developer experience

Projects like this should not be built in isolation.

We want to work with the community to continuously evolve wowOS in the following directions:

- clearer system architecture
- stronger permission and security boundaries
- a more complete app-store capability
- better SDKs and developer experience
- more realistic validation in family and personal scenarios
- a more sustainable long-term open-source ecosystem

---

## Contributing

We welcome contributions in the following areas.

### Architecture and Engineering
- system architecture design
- core module implementation
- permission and authorization models
- runtime governance and security boundaries
- app store and SDK

### Security and Privacy
- audit flows
- redaction engine
- key management
- security review
- runtime isolation

### Developer Experience
- documentation
- example projects
- debugging tools
- local development workflows
- automated testing and CI

### Real-world Feedback
- household scenario validation
- smart home integration suggestions
- local AI use cases
- architectural critique and design feedback
- real-world prioritization input

If you care about any of the following, you are very welcome to join wowOS:

- data sovereignty
- local AI
- home intelligence systems
- self-hosting / home servers
- Raspberry Pi / Linux appliance systems
- open-source system product design

---

## Current Status

**Early stage / actively evolving**

wowOS is still in an early stage. The current focus is to make the system boundary, data governance capabilities, and application integration path solid before expanding the ecosystem and use cases.

---

## Download

Pre-built images are published automatically after each successful build on the `main` branch.

👉 **[Download the latest wowOS image from GitHub Releases](https://github.com/WowData-labs/wowOS/releases/latest)**

After downloading, unzip and flash `wowos-1.0.img.zip` to an SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or `dd`. See [BUILD.md](./BUILD.md) for full instructions.

---

## License

TBD
