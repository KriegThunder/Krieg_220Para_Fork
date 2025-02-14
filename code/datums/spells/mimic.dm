/obj/effect/proc_holder/spell/mimic
	name = "Mimic"
	desc =  "Learn a new form to mimic or become one of your known forms"
	clothes_req = FALSE
	human_req = FALSE
	base_cooldown = 3 SECONDS
	action_icon_state = "genetic_morph"
	selection_activated_message = span_sinister("Click on a target to remember it's form. Click on yourself to change form.")
	create_attack_logs = FALSE
	action_icon_state = "morph_mimic"
	need_active_overlay = TRUE
	/// Which form is currently selected
	var/datum/mimic_form/selected_form
	/// Which forms the user can become
	var/list/available_forms = list()
	/// How many forms the user can remember
	var/max_forms = 5
	/// Which index will be overriden next when the user wants to remember another form
	var/next_override_index = 1
	/// If a message is shown when somebody examines the user from close range
	var/perfect_disguise = FALSE

	var/static/list/black_listed_form_types = list(
		/obj/screen,
		/obj/singularity,
		/obj/effect,
		/mob/living/simple_animal/hostile/megafauna,
		/atom/movable/lighting_object,
		/obj/machinery/dna_vault,
		/obj/machinery/power/bluespace_tap,
		/obj/structure/sign/barsign,
		/obj/machinery/atmospherics/unary/cryo_cell,
		/obj/machinery/gravity_generator
	)


/obj/effect/proc_holder/spell/mimic/create_new_targeting()
	var/datum/spell_targeting/click/T = new()
	T.include_user = TRUE // To change forms
	T.allowed_type = /atom/movable
	T.try_auto_target = FALSE
	T.click_radius = -1
	return T


/obj/effect/proc_holder/spell/mimic/valid_target(atom/target, user)
	if(is_type_in_list(target, black_listed_form_types))
		return FALSE
	if(istype(target, /atom/movable))
		var/atom/movable/AM = target
		if(AM.bound_height > world.icon_size || AM.bound_width > world.icon_size)
			return FALSE // No multitile structures
	if(user != target && ismorph(target))
		return FALSE
	return ..()


/obj/effect/proc_holder/spell/mimic/cast(list/targets, mob/user)
	var/atom/movable/A = targets[1]
	if(A == user)
		INVOKE_ASYNC(src, PROC_REF(pick_form), user)
		return

	INVOKE_ASYNC(src, PROC_REF(remember_form), A, user)


/obj/effect/proc_holder/spell/mimic/proc/remember_form(atom/movable/A, mob/user)
	if(A.name in available_forms)
		to_chat(user, span_warning("[A] is already an available form."))
		revert_cast(user)
		return

	if(length(available_forms) >= max_forms)
		to_chat(user, span_warning("You start to forget the form of [available_forms[next_override_index]] to learn a new one."))

	to_chat(user, span_sinister("You start remembering the form of [A]."))
	if(!do_after(user, 2 SECONDS, FALSE, user))
		to_chat(user, span_warning("You lose focus."))
		return

	// Forget the old form if needed
	if(length(available_forms) >= max_forms)
		qdel(available_forms[available_forms[next_override_index]]) // Delete the value using the key
		available_forms[next_override_index++] = A.name
		// Reset if needed
		if(next_override_index > max_forms)
			next_override_index = 1

	available_forms[A.name] = new /datum/mimic_form(A, user)
	to_chat(user, span_sinister("You learn the form of [A]."))


/obj/effect/proc_holder/spell/mimic/proc/pick_form(mob/user)
	if(!length(available_forms) && !selected_form)
		to_chat(user, span_warning("No available forms. Learn more forms by using this spell on other objects first."))
		revert_cast(user)
		return

	var/list/forms = list()
	if(selected_form)
		forms += "Original Form"

	forms += available_forms.Copy()
	var/what = tgui_input_list(user, "Which form do you want to become?", "Mimic", forms)
	if(!what)
		to_chat(user, span_notice("You decide against changing forms."))
		revert_cast(user)
		return

	if(what == "Original Form")
		restore_form(user)
		return
	to_chat(user, span_sinister("You start becoming [what]."))
	if(!do_after(user, 2 SECONDS, FALSE, user))
		to_chat(user, span_warning("You lose focus."))
		return
	take_form(available_forms[what], user)


/obj/effect/proc_holder/spell/mimic/proc/take_form(datum/mimic_form/form, mob/user)
	var/old_name = "[user]"
	if(ishuman(user))
		// Not fully finished yet
		var/mob/living/carbon/human/H = user
		H.name_override = form.name
	else
		user.appearance = form.appearance
		user.transform = initial(user.transform)
		user.pixel_y = initial(user.pixel_y)
		user.pixel_x = initial(user.pixel_x)
		user.layer = MOB_LAYER // Avoids weirdness when mimicing something below the vent layer

	playsound(user, "bonebreak", 75, TRUE)
	show_change_form_message(user, old_name, "[user]")
	user.create_log(MISC_LOG, "Mimicked into [user]")

	if(!selected_form)
		RegisterSignal(user, COMSIG_PARENT_EXAMINE, PROC_REF(examine_override))
		RegisterSignal(user, COMSIG_MOB_DEATH, PROC_REF(on_death))

	selected_form = form


/obj/effect/proc_holder/spell/mimic/proc/show_change_form_message(mob/user, old_name, new_name)
	user.visible_message(span_warning("[old_name] contorts and slowly becomes [new_name]!"), \
						span_sinister("You take form of [new_name]."), \
						span_italics("You hear loud cracking noises!"))


/obj/effect/proc_holder/spell/mimic/proc/restore_form(mob/user, show_message = TRUE)
	selected_form = null
	var/old_name = "[user]"

	user.cut_overlays()
	user.icon = initial(user.icon)
	user.icon_state = initial(user.icon_state)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.name_override = null
		H.regenerate_icons()
	else
		user.name = initial(user.name)
		user.desc = initial(user.desc)
		user.color = initial(user.color)

	playsound(user, "bonebreak", 150, TRUE)
	if(show_message)
		show_restore_form_message(user, old_name, "[user]")

	UnregisterSignal(user, list(COMSIG_PARENT_EXAMINE, COMSIG_MOB_DEATH))


/obj/effect/proc_holder/spell/mimic/proc/show_restore_form_message(mob/user, old_name, new_name)
	user.visible_message(span_warning("[old_name] shakes and contorts and quickly becomes [new_name]!"), \
						span_sinister("You take return to your normal self."), \
						span_italics("You hear loud cracking noises!"))


/obj/effect/proc_holder/spell/mimic/proc/examine_override(datum/source, mob/user, list/examine_list)
	examine_list.Cut()
	examine_list += selected_form.examine_text
	if(!perfect_disguise && get_dist(user, source) <= 3)
		examine_list += span_warning("It doesn't look quite right...")


/obj/effect/proc_holder/spell/mimic/proc/on_death(mob/user, gibbed)
	if(!gibbed)
		restore_form(user, FALSE)
		show_death_message(user)


/obj/effect/proc_holder/spell/mimic/proc/show_death_message(mob/user)
	user.visible_message(span_warning("[user] shakes and contorts as [user.p_they()] die[user.p_s()], returning to [user.p_their()] true form!"), \
						span_deadsay("Your disguise fails as your life forces drain away."), \
						span_italics("You hear loud cracking noises followed by a thud!"))


/datum/mimic_form
	/// How does the form look like?
	var/appearance
	/// What is the examine text paired with this form
	var/examine_text
	/// What the name of the form is
	var/name


/datum/mimic_form/New(atom/movable/form, mob/user)
	appearance = form.appearance
	examine_text = form.examine(user)
	name = form.name


/obj/effect/proc_holder/spell/mimic/morph
	action_background_icon_state = "bg_morph"


/obj/effect/proc_holder/spell/mimic/morph/create_new_handler()
	var/datum/spell_handler/morph/H = new
	return H


/obj/effect/proc_holder/spell/mimic/morph/valid_target(atom/target, user)
	if(target != user && ismorph(target))
		return FALSE
	return ..()


/obj/effect/proc_holder/spell/mimic/morph/take_form(datum/mimic_form/form, mob/living/simple_animal/hostile/morph/user)
	..()
	user.assume()

/obj/effect/proc_holder/spell/mimic/morph/restore_form(mob/living/simple_animal/hostile/morph/user, show_message = TRUE)
	..()
	user.restore()


/obj/effect/proc_holder/spell/mimic/morph/show_change_form_message(mob/user, old_name, new_name)
	user.visible_message(span_warning("[old_name] suddenly twists and changes shape, becoming a copy of [new_name]!"), \
						span_notice("You twist your body and assume the form of [new_name]."))


/obj/effect/proc_holder/spell/mimic/morph/show_restore_form_message(mob/user, old_name, new_name)
	user.visible_message(span_warning("[old_name] suddenly collapses in on itself, dissolving into a pile of green flesh!"), \
						span_notice("You reform to your normal body."))


/obj/effect/proc_holder/spell/mimic/morph/show_death_message(mob/user)
	user.visible_message(span_warning("[user] twists and dissolves into a pile of green flesh!"), \
						span_userdanger("Your skin ruptures! Your flesh breaks apart! No disguise can ward off de--"))

