"""The word filter on its own: names read as one piece, messages a word at a
time, and the innocent words each list was checked against."""

from __future__ import annotations

import unittest

from app.domain.moderation import contains_objectionable, message_is_objectionable


class MessageFilterTests(unittest.TestCase):
    def test_objectionable_messages(self) -> None:
        for text in (
            "fuck off",
            "FUCKING hell",
            "what a b1tch",
            "s.h.i.t!",
            "f_u_c_k",
            "f u c k you",
            "you,cunt",
            "ну ты и сука",
            "иди нахуй",
            "пиздец какой-то",
            "бляди",
        ):
            with self.subTest(text=text):
                self.assertTrue(message_is_objectionable(text))

    def test_ordinary_messages(self) -> None:
        for text in (
            "",
            "Hi! How was your day?",
            "Grape juice in Scunthorpe",
            "Dick Grayson says hi",
            "Поп издал книгу",
            "Страхуем дом, а потом на дебаты",
            "Застрахуй машину",
            "I s a w it at 5 pm",
            "Встречаемся в 7, у входа",
            "a b c d",
        ):
            with self.subTest(text=text):
                self.assertFalse(message_is_objectionable(text))

    def test_a_message_is_not_glued_across_words_the_way_a_name_is(self) -> None:
        # A name is short and read as one piece, spaces undone. A sentence
        # read that way would join innocent neighbours into a stem.
        self.assertTrue(contains_objectionable("Fu ck"))
        self.assertTrue(contains_objectionable("Поп издал"))
        self.assertFalse(message_is_objectionable("Поп издал"))


if __name__ == "__main__":
    unittest.main()
