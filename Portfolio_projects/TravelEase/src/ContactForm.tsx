import { useState } from "react";
import { useForm } from "react-hook-form";

type FormData = {
  name: string;
  email: string;
  phone?: string;
  inquiry_type: string;
  message: string;
};

function ContactForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    reset,
  } = useForm<FormData>({
    defaultValues: {
      inquiry_type: "vacation package",
    },
  });
  const [submissionResult, setSubmissionResult] = useState<string | null>(null);

  const onSubmit = async (data: FormData) => {
    setSubmissionResult(null);

    try {
      const apiEndpoint = import.meta.env.VITE_API_ENDPOINT;
      const response = await fetch(`${apiEndpoint}/submit`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(`API error: ${response.statusText} - ${errorData.error}`);
      }

      const result = await response.json();
      const referenceId = result.submission_id || "submitted";

      setSubmissionResult(
        `🎉 Thank you for your submission! Your reference number is: ${referenceId}. We'll reply within 24 hours!`
      );
      reset();
    } catch (error) {
      console.error("Error submitting form:", error);
      setSubmissionResult(
        "😔 There was an error submitting your form. Please try again."
      );
    }
  };

  return (
    <div>
      <h2>Contact Us</h2>
      <form onSubmit={handleSubmit(onSubmit)}>
        <div>
          <label htmlFor="name">Name:</label>
          <input
            type="text"
            id="name"
            {...register("name", { required: "Name is required" })}
          />
          {errors.name && <p className="error">{errors.name.message}</p>}
        </div>
        <div>
          <label htmlFor="email">Email:</label>
          <input
            type="email"
            id="email"
            {...register("email", {
              required: "Email is required",
              pattern: {
                value: /^\S+@\S+$/i,
                message: "Invalid email address",
              },
            })}
          />
          {errors.email && <p className="error">{errors.email.message}</p>}
        </div>
        <div>
          <label htmlFor="phone">Phone (optional):</label>
          <input
            type="tel"
            id="phone"
            {...register("phone", {
              pattern: {
                value: /^[0-9+-]*$/,
                message: "Invalid phone number",
              },
            })}
          />
          {errors.phone && <p className="error">{errors.phone.message}</p>}
        </div>
        <div>
          <label htmlFor="inquiryType">Inquiry Type:</label>
          <select
            id="inquiryType"
            {...register("inquiry_type", { required: "Inquiry type is required" })}
          >
            <option value="vacation package">Vacation Package</option>
            <option value="pricing">Pricing</option>
            <option value="availability">Availability</option>
          </select>
          {errors.inquiry_type && (
            <p className="error">{errors.inquiry_type.message}</p>
          )}
        </div>
        <div>
          <label htmlFor="message">Message:</label>
          <textarea
            id="message"
            {...register("message", { required: "Message is required" })}
          />
          {errors.message && <p className="error">{errors.message.message}</p>}
        </div>
        <button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Submitting..." : "Submit"}
        </button>
      </form>
      {submissionResult && <p>{submissionResult}</p>}
    </div>
  );
}

export default ContactForm;
