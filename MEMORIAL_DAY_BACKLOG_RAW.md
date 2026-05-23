# Memorial Day Backlog — Raw (verbatim from user, 2026-05-22)

Source of truth for `MEMORIAL_DAY_BACKLOG_PLAN.md`. These are the original 18 items the user wrote in their notes app. Captured verbatim with minor whitespace cleanup; typos and informal phrasing preserved.

---

**1.** Bring the tutorial after onboarding for a new user. User swipes on start logging. The see the tutorial and do not make it interact-able. User should click on next and then go to the Homescreen.

**2.** After tutorial that provide and show th euser logging tips. It is important that the user knows how frequently we surface the logging clue so that the user is accuratly logging.

**3.** Redesign the UI for failure. So when there is. backend issue and if there parse issue we say things like cant reach backend or retry parse. It llook really ugly on the row. It should show at the same place where we show the offlining text/syncing text. The retry parse should shown line as a text with underlined and not as a button.

**4.** Soemtimes when th euser makes an entry, we show logging tips un row. I think we should improve that UI. Make it a pop up that have a call to action for Loging tips ang skip opvtion.

**5.** Work on the UI that shows if teh user is signing up using yheisame email second time we show them a screen where they select same same profile or update profile with new info. I think that screen needs to bne redesigned.

**6.** Upate the Ui for profile section. Make it clean and modern. It is too colorful right now. Maitain some color but tone it down/

**7.** Move the daily targets bento card to the graphs section. Make daily targets on the top and then have the segmented controller for other graphs.

**8.** I am seeing aretry message in the rewards screen most of the time. Check what that issue is.

**9.** It feels like the camera is using the wide angel camera. We need to use the normal primary camera.

**10.** Improve the UI for the logging drawer. There are 2 trypes of drawer. One that opens after taking picture and th eother one that opens when I click on the calories. Both those drawers need toi be updated design wise to be more crisp and cleaner design with better diffrenciation with categories inside. It needs to be cleaner and clean.

**11.** I feel like there is a huge gap on the serving size selection. We can only select number of servings but we do not have the option to select the type of serving. For example if the app detects a cup but actually it's a glass, I can not change it from cup to glass.

**12.** Similarly I think we need to have, with the serving size selection, serving type selection and I think both of them need to be native pickers. That way the user can just click and pick a different number instead of having the 0.5 increment. I think the user can just customize it. The app still defaults to whatever is the best but then the users should have the ability to customize as much as possible.

**13.** I want to remove the mention of Gemini Nutrition Database from the food app thought process. It's good that we show the thought process but I think we should increase the thought process a little bit and specifically call out how the app came up with the food item. Make the thought process more robust but at the end of the day we should not mention the name of Gemini Nutrition Database.

**14.** So the current sequence is that let's say the user is onboarding and after onboarding they see the final screen where they can swipe to start logging. After doing that they get on the home screen where there is a three-step tutorial which we just decided that we will do next, next, next, and it's not going to be interactable. On the last one when they click on Done, one thing that I want to design on the screen is that we need to somehow tell the user that they can swipe left and right to go between different days. I think that is something that needs to come. That should be something that is interactable. We just animate an arrow on the screen. User swipes left and we should say "Swipe left". User swipes left and then on the left screen we say "Swipe right" and then user swipes right. That's how they will know how to go back and forth with the days to kind of see different days. I think that is something also we need to build and test.

**15.** Whenever we are flashing a badge on the screen that the user just earned or the user goes into the badges section and they click on the badge to see what they earned, on that screen it should not automatically dismiss. It dismisses automatically but we should have button in white at the bottom which says something fun. I don't know. I don't want to say "Okay I understand" and things like that but I wanted to say something fun so maybe suggest a word that we can say over there.

**16.** The graph icon is three bar graphs right now at the bottom right. I think we need to update that icon as well. It feels and looks a little bit weird.

**17.** Under the widgets drawer under profile when I click on it on the home, whatever widget you are showing doesn't really reflect the widget that we are showing outside. You need to see what the issue is over there and we need to make sure that that widget reflects whatever we are showing actually on the home screen. On that screen on the home tab itself if you select next under the add daily widget section, there is more text getting added and that card just increases in height and changes the height. That should not happen. It should be a consistent height. Maybe you can give it a longer height initially but I would suggest that you make sure that the card doesn't move up and down for the daily add widget under the home tab. The home tab is just called home right now so maybe just call it home screen and the lock tab is called lock so just call it lock screen. In the lock screen tab the widget and everything seems really broken right now. The widget is not shown properly. It just says 8 calories instead of 842 calories and things are getting cut off on small size phones. Maybe we need to just check why that is happening. Maybe that is something that you need to take a look at.

**18.** The saved button only shows up when I click on the screen to type something. I think we should by default show the save button at all times. Right now the icon looks like a bookmark icon. Maybe change that icon to something else and remove the word "saved" and let's see if the user understands it or not. We just need to have a similar circle like all the other circles that we have in the center of the screen. Let's see how that looks and maybe we will figure out a way to change it.
