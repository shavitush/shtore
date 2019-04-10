# shtore - shavit's store

A currently private SourceMod store plugin designed for [YourGame.co.il](https://yourgame.co.il/).

## Core features

* Easy to setup. Not plug-n-play sadly but configuration is simple.
* Written in modern SourcePawn syntax, making use of `enum struct` for pseudo-object feeling.
* Very lightweight compared to other store plugins.
* Simple item equipping mechanism.
* Decent pseudo-random credit distribution.
* Database structure can scale very well.

## Missing features

Will probably release this to the public once they're done:

- [ ] Access to items/categories via flags/overrides.
- [ ] Config file with categories.
- [ ] Admin commands.
- [ ] Logging.
- [ ] Natives. (manipulating and obtaining user data, getting data about items/categories)
- [ ] Forwards. (item purchase/sale, credit distribution)
- [ ] Some sort of interface for adding and editing items.

### Build status

[![Build status](https://travis-ci.com/shavitush/shtore.svg?token=XKPoLu2iqpgbenWpSLsf&branch=master)](https://travis-ci.com/shavitush/shtore)